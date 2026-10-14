package clientconf

import (
	"strings"
	"testing"

	"github.com/Sent-hen/VPN/internal/wgkey"
)

func testServer(t *testing.T, devicePub string) []byte {
	t.Helper()
	return []byte(`{
		"endpoint": "198.51.100.10:51820",
		"server_ipv4": "198.51.100.10",
		"admin_user": "vpnadmin",
		"dns": ["10.8.0.1", "fd86:ea04:1115::1"],
		"peers": {
			"laptop": {"public_key": "` + devicePub + `", "ipv4": "10.8.0.2", "ipv6": "fd86:ea04:1115::2"}
		}
	}`)
}

func keys(t *testing.T) (priv, pub, serverPub wgkey.Key) {
	t.Helper()
	priv, _ = wgkey.GeneratePrivate()
	pub, _ = priv.Public()
	serverPriv, _ := wgkey.GeneratePrivate()
	serverPub, _ = serverPriv.Public()
	return priv, pub, serverPub
}

func TestBuildAndRender(t *testing.T) {
	priv, pub, serverPub := keys(t)
	s, err := ParseServer(testServer(t, pub.String()))
	if err != nil {
		t.Fatal(err)
	}
	c, err := Build(s, "laptop", priv, serverPub)
	if err != nil {
		t.Fatal(err)
	}
	got := c.Render()
	want := "[Interface]\n" +
		"PrivateKey = " + priv.String() + "\n" +
		"Address = 10.8.0.2/32, fd86:ea04:1115::2/128\n" +
		"DNS = 10.8.0.1, fd86:ea04:1115::1\n" +
		"\n[Peer]\n" +
		"PublicKey = " + serverPub.String() + "\n" +
		"AllowedIPs = 0.0.0.0/0, ::/0\n" +
		"Endpoint = 198.51.100.10:51820\n" +
		"PersistentKeepalive = 25\n"
	if got != want {
		t.Fatalf("Render() =\n%s\nwant\n%s", got, want)
	}
}

func TestBuildRejectsKeyMismatch(t *testing.T) {
	priv, _, serverPub := keys(t)
	_, otherPub, _ := keys(t)
	s, err := ParseServer(testServer(t, otherPub.String()))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Build(s, "laptop", priv, serverPub); err == nil || !strings.Contains(err.Error(), "public key") {
		t.Fatalf("Build error = %v, want key mismatch", err)
	}
}

func TestBuildRejectsUnknownDevice(t *testing.T) {
	priv, pub, serverPub := keys(t)
	s, _ := ParseServer(testServer(t, pub.String()))
	if _, err := Build(s, "phone", priv, serverPub); err == nil {
		t.Fatal("Build succeeded for a device the server does not know")
	}
}

func TestParseServerRejectsInjection(t *testing.T) {
	for _, raw := range []string{
		`{"endpoint": "198.51.100.10:51820", "server_ipv4": "-oProxyCommand=calc", "admin_user": "vpnadmin"}`,
		`{"endpoint": "198.51.100.10:51820", "server_ipv4": "198.51.100.10", "admin_user": "-oProxyCommand=calc"}`,
		`{"endpoint": "evil.example\n[Peer]", "server_ipv4": "198.51.100.10", "admin_user": "vpnadmin"}`,
		`{"endpoint": "198.51.100.10:51820", "server_ipv4": "198.51.100.10", "admin_user": "vpnadmin", "dns": ["1.1.1.1\nPostUp = calc"]}`,
	} {
		if _, err := ParseServer([]byte(raw)); err == nil {
			t.Errorf("ParseServer accepted %s", raw)
		}
	}
}
