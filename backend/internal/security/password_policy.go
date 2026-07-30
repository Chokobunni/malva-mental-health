package security

import (
	"errors"
	"unicode"
)

var (
	ErrPasswordTooShort     = errors.New("password must be at least 8 characters")
	ErrPasswordTooLong      = errors.New("password must be at most 128 characters")
	ErrPasswordNoUpper      = errors.New("password must contain at least one uppercase letter")
	ErrPasswordNoLower      = errors.New("password must contain at least one lowercase letter")
	ErrPasswordNoDigit      = errors.New("password must contain at least one digit")
	ErrPasswordNoSpecial    = errors.New("password must contain at least one special character")
	ErrPasswordCommon       = errors.New("password is too common")
	ErrPasswordHasEmail     = errors.New("password cannot contain your email address")
)

var commonPasswords = map[string]bool{
	"password":    true,
	"12345678":    true,
	"qwerty123":   true,
	"letmein":     true,
	"welcome1":    true,
	"admin123":    true,
	"password1":   true,
	"123456789":   true,
	"abc123456":   true,
	"malva1234":   true,
}

func ValidatePassword(password, email string) error {
	if len(password) < 8 {
		return ErrPasswordTooShort
	}
	if len(password) > 128 {
		return ErrPasswordTooLong
	}
	if commonPasswords[password] {
		return ErrPasswordCommon
	}
	if email != "" {
		emailLower := email
		for i := 0; i < len(emailLower); i++ {
			if emailLower[i] == '@' {
				emailLower = emailLower[:i]
				break
			}
		}
		if len(emailLower) >= 3 {
			for i := 0; i <= len(password)-len(emailLower); i++ {
				match := true
				for j := 0; j < len(emailLower); j++ {
					if unicode.ToLower(rune(password[i+j])) != unicode.ToLower(rune(emailLower[j])) {
						match = false
						break
					}
				}
				if match {
					return ErrPasswordHasEmail
				}
			}
		}
	}
	var hasUpper, hasLower, hasDigit, hasSpecial bool
	for _, ch := range password {
		switch {
		case unicode.IsUpper(ch):
			hasUpper = true
		case unicode.IsLower(ch):
			hasLower = true
		case unicode.IsDigit(ch):
			hasDigit = true
		case unicode.IsPunct(ch) || unicode.IsSymbol(ch):
			hasSpecial = true
		}
	}
	if !hasUpper {
		return ErrPasswordNoUpper
	}
	if !hasLower {
		return ErrPasswordNoLower
	}
	if !hasDigit {
		return ErrPasswordNoDigit
	}
	if !hasSpecial {
		return ErrPasswordNoSpecial
	}
	return nil
}

func PasswordStrengthScore(password string) int {
	score := 0
	if len(password) >= 8 {
		score++
	}
	if len(password) >= 12 {
		score++
	}
	if len(password) >= 16 {
		score++
	}
	var hasUpper, hasLower, hasDigit, hasSpecial bool
	for _, ch := range password {
		switch {
		case unicode.IsUpper(ch):
			hasUpper = true
		case unicode.IsLower(ch):
			hasLower = true
		case unicode.IsDigit(ch):
			hasDigit = true
		case unicode.IsPunct(ch) || unicode.IsSymbol(ch):
			hasSpecial = true
		}
	}
	if hasUpper {
		score++
	}
	if hasLower {
		score++
	}
	if hasDigit {
		score++
	}
	if hasSpecial {
		score++
	}
	if score > 5 {
		score = 5
	}
	return score
}
