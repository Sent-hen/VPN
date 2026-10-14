package wgkey

import (
	"encoding/hex"
	"testing"
)

// RFC 7748 section 6.1, Alice's key pair.
func TestPublicMatchesRFC7748(t *testing.T) {
	privBytes, _ := hex.DecodeString("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
	wantPub := "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"

	var priv Key
	copy(priv[:], privBytes)
	pub, err := priv.Public()
	if err != nil {
		t.Fatal(err)
	}
	if got := hex.EncodeToString(pub[:]); got != wantPub {
		t.Fatalf("public key = %s, want %s", got, wantPub)
	}
}

func TestGeneratePrivateIsClamped(t *testing.T) {
	k, err := GeneratePrivate()
	if err != nil {
		t.Fatal(err)
	}
	if k[0]&7 != 0 || k[31]&128 != 0 || k[31]&64 == 0 {
		t.Fatalf("key not clamped: first=%08b last=%08b", k[0], k[31])
	}
}

func TestParseRoundTrip(t *testing.T) {
	k, _ := GeneratePrivate()
	got, err := Parse(k.String())
	if err != nil {
		t.Fatal(err)
	}
	if got != k {
		t.Fatal("round trip changed the key")
	}
}

func TestParseRejectsBadInput(t *testing.T) {
	for _, s := range []string{
		"",
		"not base64!",
		"AAAA",
		"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", // 36 bytes
	} {
		if _, err := Parse(s); err == nil {
			t.Errorf("Parse(%q) succeeded, want error", s)
		}
	}
}
