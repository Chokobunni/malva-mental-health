package auth

import "testing"

func TestGenerateRefreshTokenReturnsHighEntropyToken(t *testing.T) {
	first, err := GenerateRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	second, err := GenerateRefreshToken()
	if err != nil {
		t.Fatal(err)
	}

	if len(first) < 40 {
		t.Fatalf("expected long refresh token, got length %d", len(first))
	}
	if first == second {
		t.Fatal("refresh tokens should be unique")
	}
}

func TestHashRefreshTokenIsStableAndDoesNotExposeToken(t *testing.T) {
	token := "refresh-token-example"
	first := HashRefreshToken(token)
	second := HashRefreshToken(token)

	if first != second {
		t.Fatal("hash should be stable")
	}
	if first == token {
		t.Fatal("hash must not equal raw token")
	}
	if len(first) != 64 {
		t.Fatalf("expected sha256 hex length 64, got %d", len(first))
	}
}
