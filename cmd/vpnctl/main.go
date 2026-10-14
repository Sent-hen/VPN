// Command vpnctl is the client-side tool for the personal VPN until the daemon
// and UI exist. It creates device keys locally and turns the provisioner's
// Terraform output into a WireGuard client config.
//
//	vpnctl keygen -device laptop
//	vpnctl pubkey -device laptop
//	vpnctl client-config -device laptop -terraform-dir provisioning/hetzner
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/Sent-hen/VPN/internal/clientconf"
	"github.com/Sent-hen/VPN/internal/keystore"
	"github.com/Sent-hen/VPN/internal/wgkey"
)

const usage = `usage: vpnctl <command> [flags]

commands:
  keygen         create a private key for this device and print its public key
  pubkey         print the public key for an existing device key
  client-config  write a WireGuard config for this device from Terraform output

Run "vpnctl <command> -h" for the flags of each command.
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "keygen":
		err = keygen(os.Args[2:])
	case "pubkey":
		err = pubkey(os.Args[2:])
	case "client-config":
		err = clientConfig(os.Args[2:])
	case "-h", "--help", "help":
		fmt.Print(usage)
	default:
		fmt.Fprintf(os.Stderr, "vpnctl: unknown command %q\n\n%s", os.Args[1], usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "vpnctl: %v\n", err)
		os.Exit(1)
	}
}

func keygen(args []string) error {
	fs := flag.NewFlagSet("keygen", flag.ExitOnError)
	device := fs.String("device", "", "device name, e.g. laptop (required)")
	force := fs.Bool("force", false, "replace an existing key; the server must then be given the new public key")
	fs.Parse(args)

	store, err := keystore.Default()
	if err != nil {
		return err
	}
	priv, err := store.Create(*device, *force)
	if errors.Is(err, keystore.ErrExists) {
		return fmt.Errorf("%w (use -force to replace it, or `vpnctl pubkey` to see the existing public key)", err)
	}
	if err != nil {
		return err
	}
	pub, err := priv.Public()
	if err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Private key saved in %s. It never needs to leave this device.\n", store.Dir)
	fmt.Fprintln(os.Stderr, "Public key (put this in terraform.tfvars):")
	fmt.Println(pub)
	return nil
}

func pubkey(args []string) error {
	fs := flag.NewFlagSet("pubkey", flag.ExitOnError)
	device := fs.String("device", "", "device name (required)")
	fs.Parse(args)

	store, err := keystore.Default()
	if err != nil {
		return err
	}
	priv, err := store.Load(*device)
	if err != nil {
		return err
	}
	pub, err := priv.Public()
	if err != nil {
		return err
	}
	fmt.Println(pub)
	return nil
}

func clientConfig(args []string) error {
	fs := flag.NewFlagSet("client-config", flag.ExitOnError)
	device := fs.String("device", "", "device name (required)")
	tfDir := fs.String("terraform-dir", filepath.Join("provisioning", "hetzner"), "Terraform directory to read the `client` output from")
	tfOutput := fs.String("terraform-output", "", "read `terraform output -json client` from this file instead of running terraform")
	serverKey := fs.String("server-pubkey", "", "server public key; fetched over SSH when empty")
	out := fs.String("out", "", "where to write the config (default: <device>.conf next to the device key)")
	fs.Parse(args)

	store, err := keystore.Default()
	if err != nil {
		return err
	}
	priv, err := store.Load(*device)
	if err != nil {
		return fmt.Errorf("loading device key (run `vpnctl keygen -device %s` first): %w", *device, err)
	}

	var raw []byte
	if *tfOutput != "" {
		raw, err = os.ReadFile(*tfOutput)
	} else {
		raw, err = run("terraform", "-chdir="+*tfDir, "output", "-json", "client")
	}
	if err != nil {
		return err
	}
	server, err := clientconf.ParseServer(raw)
	if err != nil {
		return err
	}

	keyText := *serverKey
	if keyText == "" {
		fmt.Fprintf(os.Stderr, "Fetching server public key from %s@%s (waits for first-boot setup to finish)...\n", server.AdminUser, server.ServerIPv4)
		b, err := run("ssh",
			"-o", "BatchMode=yes",
			"-o", "StrictHostKeyChecking=accept-new",
			"--", server.AdminUser+"@"+server.ServerIPv4,
			// `status --wait` exits non-zero on recoverable warnings, so its
			// result is ignored; vpn-peer fails on its own if setup did not run.
			"cloud-init status --wait >/dev/null; sudo vpn-peer server-pubkey")
		if err != nil {
			return fmt.Errorf("fetching server public key (is your IP in admin_cidrs?): %w", err)
		}
		keyText = strings.TrimSpace(string(b))
	}
	serverPub, err := wgkey.Parse(keyText)
	if err != nil {
		return fmt.Errorf("server public key: %w", err)
	}

	cfg, err := clientconf.Build(server, *device, priv, serverPub)
	if err != nil {
		return err
	}
	path := *out
	if path == "" {
		path = filepath.Join(store.Dir, *device+".conf")
	}
	// The config holds the private key, so it gets the same protection.
	if err := os.WriteFile(path, []byte(cfg.Render()), 0o600); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Wrote %s\nImport it in the WireGuard app (Add Tunnel > Import tunnel(s) from file), then delete the file.\n", path)
	return nil
}

// run executes a command and returns its stdout, folding stderr into the
// error on failure.
func run(name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	b, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(stderr.String()))
	}
	return b, nil
}
