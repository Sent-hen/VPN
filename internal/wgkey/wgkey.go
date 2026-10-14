// Package wgkey generates and encodes WireGuard (Curve25519) keys using only
// the standard library.
package wgkey

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"fmt"
)

// Key is a raw 32-byte WireGuard private or public key.
type Key [32]byte

// GeneratePrivate returns a new private key, clamped the same way `wg genkey`
// clamps it.
func GeneratePrivate() (Key, error) {
	var k Key
	if _, err := rand.Read(k[:]); err != nil {
		return Key{}, fmt.Errorf("reading random bytes: %w", err)
	}
	k[0] &= 248
	k[31] = (k[31] & 127) | 64
	return k, nil
}

// Public derives the public key for private key k.
func (k Key) Public() (Key, error) {
	priv, err := ecdh.X25519().NewPrivateKey(k[:])
	if err != nil {
		return Key{}, err
	}
	var pub Key
	copy(pub[:], priv.PublicKey().Bytes())
	return pub, nil
}

// String returns the base64 form used in WireGuard config files.
func (k Key) String() string {
	return base64.StdEncoding.EncodeToString(k[:])
}

// Parse decodes a base64 WireGuard key.
func Parse(s string) (Key, error) {
	b, err := base64.StdEncoding.Strict().DecodeString(s)
	if err != nil {
		return Key{}, fmt.Errorf("invalid key encoding: %w", err)
	}
	if len(b) != len(Key{}) {
		return Key{}, fmt.Errorf("invalid key length %d, want 32", len(b))
	}
	var k Key
	copy(k[:], b)
	return k, nil
}
