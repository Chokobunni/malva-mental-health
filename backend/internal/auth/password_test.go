package auth

import (
	"strings"
	"testing"
)

func TestHashPasswordAcceptsLongInput(t *testing.T) {
	long := "sso-google-" + strings.Repeat("a", 100)
	hash, err := HashPassword(long)
	if err != nil {
		t.Fatalf("HashPassword panjang harus sukses, dapat: %v", err)
	}
	if !CheckPassword(hash, long) {
		t.Fatal("CheckPassword harus menerima password panjang yang sama")
	}
	if CheckPassword(hash, long+"x") {
		t.Fatal("password berbeda harus ditolak")
	}
}

func TestHashPasswordRoundTripNormal(t *testing.T) {
	hash, err := HashPassword("Dokter12345")
	if err != nil {
		t.Fatalf("HashPassword error: %v", err)
	}
	if !CheckPassword(hash, "Dokter12345") {
		t.Fatal("password benar harus diterima")
	}
	if CheckPassword(hash, "salah") {
		t.Fatal("password salah harus ditolak")
	}
}
