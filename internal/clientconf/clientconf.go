// Package clientconf builds WireGuard client configs from the provisioner's
// Terraform output.
package clientconf

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"regexp"
	"strings"

	"github.com/Sent-hen/VPN/internal/wgkey"
)

// Server is the `client` output of the provisioning Terraform module.
type Server struct {
	Endpoint   string          `json:"endpoint"`
	ServerIPv4 string          `json:"server_ipv4"`
	AdminUser  string          `json:"admin_user"`
	DNS        []string        `json:"dns"`
	Peers      map[string]Peer `json:"peers"`
}

// Peer is one device as registered on the server.
type Peer struct {
	PublicKey string `json:"public_key"`
	IPv4      string `json:"ipv4"`
	IPv6      string `json:"ipv6"`
}

var validUser = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,31}$`)

// ParseServer decodes and validates `terraform output -json client`. The
// values end up in an ssh command line and a config file, so anything that is
// not the expected shape is rejected rather than escaped.
func ParseServer(raw []byte) (Server, error) {
	var s Server
	if err := json.Unmarshal(raw, &s); err != nil {
		return Server{}, fmt.Errorf("parsing terraform output: %w", err)
	}
	if _, err := netip.ParseAddrPort(s.Endpoint); err != nil {
		return Server{}, fmt.Errorf("endpoint %q: %w", s.Endpoint, err)
	}
	if _, err := netip.ParseAddr(s.ServerIPv4); err != nil {
		return Server{}, fmt.Errorf("server_ipv4 %q: %w", s.ServerIPv4, err)
	}
	if !validUser.MatchString(s.AdminUser) {
		return Server{}, fmt.Errorf("admin_user %q is not a valid user name", s.AdminUser)
	}
	for _, d := range s.DNS {
		if _, err := netip.ParseAddr(d); err != nil {
			return Server{}, fmt.Errorf("dns %q: %w", d, err)
		}
	}
	return s, nil
}

// Config is a WireGuard client config that sends all traffic through the
// tunnel.
type Config struct {
	PrivateKey      wgkey.Key
	Addresses       []netip.Prefix
	DNS             []netip.Addr
	ServerPublicKey wgkey.Key
	Endpoint        netip.AddrPort
}

// Build makes the config for one device. It checks that the public key the
// server has for the device matches the device's own private key, which
// catches a stale key in terraform.tfvars before it becomes a silent
// handshake failure.
func Build(s Server, device string, priv, serverPub wgkey.Key) (Config, error) {
	p, ok := s.Peers[device]
	if !ok {
		return Config{}, fmt.Errorf("device %q is not in the server's peer list", device)
	}
	pub, err := priv.Public()
	if err != nil {
		return Config{}, err
	}
	if p.PublicKey != pub.String() {
		return Config{}, fmt.Errorf("server has public key %s for %q, but this device's key is %s", p.PublicKey, device, pub)
	}

	c := Config{PrivateKey: priv, ServerPublicKey: serverPub}
	if c.Endpoint, err = netip.ParseAddrPort(s.Endpoint); err != nil {
		return Config{}, err
	}
	for _, a := range []string{p.IPv4, p.IPv6} {
		addr, err := netip.ParseAddr(a)
		if err != nil {
			return Config{}, fmt.Errorf("peer address %q: %w", a, err)
		}
		c.Addresses = append(c.Addresses, netip.PrefixFrom(addr, addr.BitLen()))
	}
	for _, d := range s.DNS {
		addr, err := netip.ParseAddr(d)
		if err != nil {
			return Config{}, err
		}
		c.DNS = append(c.DNS, addr)
	}
	return c, nil
}

// Render returns the config in wg-quick format, which the WireGuard for
// Windows app can import. Routing both 0.0.0.0/0 and ::/0 through the tunnel
// is what prevents IPv6 leaks, and on Windows it also turns on the app's
// "block untunneled traffic" kill switch.
func (c Config) Render() string {
	var b strings.Builder
	b.WriteString("[Interface]\n")
	fmt.Fprintf(&b, "PrivateKey = %s\n", c.PrivateKey)
	fmt.Fprintf(&b, "Address = %s\n", join(c.Addresses))
	if len(c.DNS) > 0 {
		fmt.Fprintf(&b, "DNS = %s\n", join(c.DNS))
	}
	b.WriteString("\n[Peer]\n")
	fmt.Fprintf(&b, "PublicKey = %s\n", c.ServerPublicKey)
	b.WriteString("AllowedIPs = 0.0.0.0/0, ::/0\n")
	fmt.Fprintf(&b, "Endpoint = %s\n", c.Endpoint)
	// Keeps NAT mappings on café and hotel routers alive while idle.
	b.WriteString("PersistentKeepalive = 25\n")
	return b.String()
}

func join[T fmt.Stringer](items []T) string {
	s := make([]string, len(items))
	for i, it := range items {
		s[i] = it.String()
	}
	return strings.Join(s, ", ")
}
