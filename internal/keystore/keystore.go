// Package keystore keeps device private keys on the local machine.
//
// Keys are stored as files in a per-user, non-roaming directory
// (%LOCALAPPDATA%\PersonalVPN\devices on Windows). That directory is only
// readable by the user, but the files themselves are not encrypted; moving
// them into DPAPI or the Windows Credential Manager is planned for the daemon
// (see docs/roadmap.md).
package keystore

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	"github.com/Sent-hen/VPN/internal/wgkey"
)

var validName = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)

// ErrExists is returned by Create when the device already has a key.
var ErrExists = errors.New("device key already exists")

// Store is a directory of device keys.
type Store struct {
	Dir string
}

// Default returns the store in the user's local application data directory.
func Default() (Store, error) {
	if runtime.GOOS == "windows" {
		if dir := os.Getenv("LOCALAPPDATA"); dir != "" {
			return Store{Dir: filepath.Join(dir, "PersonalVPN", "devices")}, nil
		}
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return Store{}, err
	}
	return Store{Dir: filepath.Join(dir, "personal-vpn", "devices")}, nil
}

// ValidateName reports whether name can be used as a device name. The same
// rule is enforced by Terraform and by vpn-peer on the server.
func ValidateName(name string) error {
	if !validName.MatchString(name) {
		return fmt.Errorf("invalid device name %q: use lowercase letters, digits and dashes (max 32)", name)
	}
	return nil
}

func (s Store) path(name string) string {
	return filepath.Join(s.Dir, name+".key")
}

// Create generates and saves a private key for a device. Unless overwrite is
// set, it refuses to replace an existing key.
func (s Store) Create(name string, overwrite bool) (wgkey.Key, error) {
	if err := ValidateName(name); err != nil {
		return wgkey.Key{}, err
	}
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return wgkey.Key{}, err
	}
	key, err := wgkey.GeneratePrivate()
	if err != nil {
		return wgkey.Key{}, err
	}
	flags := os.O_WRONLY | os.O_CREATE | os.O_EXCL
	if overwrite {
		flags = os.O_WRONLY | os.O_CREATE | os.O_TRUNC
	}
	f, err := os.OpenFile(s.path(name), flags, 0o600)
	if errors.Is(err, os.ErrExist) {
		return wgkey.Key{}, fmt.Errorf("%w: %s", ErrExists, s.path(name))
	}
	if err != nil {
		return wgkey.Key{}, err
	}
	if _, err := f.WriteString(key.String() + "\n"); err != nil {
		f.Close()
		return wgkey.Key{}, err
	}
	return key, f.Close()
}

// Load reads the private key for a device.
func (s Store) Load(name string) (wgkey.Key, error) {
	if err := ValidateName(name); err != nil {
		return wgkey.Key{}, err
	}
	b, err := os.ReadFile(s.path(name))
	if err != nil {
		return wgkey.Key{}, err
	}
	return wgkey.Parse(strings.TrimSpace(string(b)))
}
