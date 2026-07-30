package auth

import (
	"strings"
	"testing"
)

func TestManagerIssuesAndVerifiesToken(t *testing.T) {
	manager := NewManager("this-secret-is-long-enough-for-local-tests")
	token, err := manager.Issue("user-1", "patient")
	if err != nil {
		t.Fatalf("Issue returned error: %v", err)
	}
	claims, err := manager.Verify(token)
	if err != nil {
		t.Fatalf("Verify returned error: %v", err)
	}
	if claims.Subject != "user-1" || claims.Role != "patient" {
		t.Fatalf("claims = %#v, want user-1/patient", claims)
	}
}

func TestManagerRejectsTamperedToken(t *testing.T) {
	manager := NewManager("this-secret-is-long-enough-for-local-tests")
	token, err := manager.Issue("user-1", "patient")
	if err != nil {
		t.Fatalf("Issue returned error: %v", err)
	}
	tampered := strings.TrimSuffix(token, token[len(token)-1:]) + "x"
	if _, err := manager.Verify(tampered); err == nil {
		t.Fatal("expected tampered token to be rejected")
	}
}
