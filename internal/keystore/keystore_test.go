package keystore

import (
	"errors"
	"testing"
)

func TestCreateAndLoad(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	created, err := s.Create("laptop", false)
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := s.Load("laptop")
	if err != nil {
		t.Fatal(err)
	}
	if loaded != created {
		t.Fatal("loaded key differs from created key")
	}
}

func TestCreateRefusesOverwrite(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	first, _ := s.Create("laptop", false)
	if _, err := s.Create("laptop", false); !errors.Is(err, ErrExists) {
		t.Fatalf("second Create error = %v, want ErrExists", err)
	}
	if k, _ := s.Load("laptop"); k != first {
		t.Fatal("refused Create still changed the key")
	}
	second, err := s.Create("laptop", true)
	if err != nil {
		t.Fatal(err)
	}
	if second == first {
		t.Fatal("overwrite kept the old key")
	}
}

func TestRejectsPathTraversal(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	for _, name := range []string{"", "../evil", `..\evil`, "Laptop", "a b", "-x"} {
		if _, err := s.Create(name, false); err == nil {
			t.Errorf("Create(%q) succeeded, want error", name)
		}
	}
}
