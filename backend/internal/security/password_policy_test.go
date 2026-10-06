package security

import (
	"strings"
	"testing"
)

func TestIndonesianMessageCoversAllErrors(t *testing.T) {
	errs := []error{
		ErrPasswordTooShort, ErrPasswordTooLong, ErrPasswordCommon,
		ErrPasswordHasEmail, ErrPasswordNoUpper, ErrPasswordNoLower,
		ErrPasswordNoDigit, ErrPasswordNoSpecial,
	}
	for _, err := range errs {
		msg := IndonesianMessage(err)
		if strings.TrimSpace(msg) == "" {
			t.Fatalf("pesan kosong untuk %v", err)
		}
		if strings.Contains(msg, "password must") {
			t.Fatalf("pesan masih Inggris untuk %v: %s", err, msg)
		}
		if got := ValidatePassword(passwordForError(err), "user@example.com"); got != err {
			t.Fatalf("ValidatePassword tidak mengembalikan %v", err)
		}
	}
}

func passwordForError(err error) string {
	switch err {
	case ErrPasswordTooShort:
		return "Ab1#"
	case ErrPasswordTooLong:
		return strings.Repeat("Aa1#", 40)
	case ErrPasswordCommon:
		return "malva1234"
	case ErrPasswordHasEmail:
		return "User#1234"
	case ErrPasswordNoUpper:
		return "rendah#123"
	case ErrPasswordNoLower:
		return "TINGGI#123"
	case ErrPasswordNoDigit:
		return "TanpaAngka#"
	case ErrPasswordNoSpecial:
		return "TanpaSimbol123"
	default:
		return "Valid#1234"
	}
}
