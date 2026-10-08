package auth

import (
	"crypto/sha256"
	"encoding/hex"

	"golang.org/x/crypto/bcrypt"
)

// bcryptMaxBytes adalah batas keras bcrypt: input >72 byte ditolak
// (ErrPasswordTooLong) pada x/crypto versi baru.
const bcryptMaxBytes = 72

// normalizePassword memastikan input bcrypt selalu <=72 byte. Password
// panjang dipadatkan dengan SHA-256 (hex 64 byte) — praktik standar bcrypt.
// Password <=72 byte dibiarkan apa adanya agar hash lama tetap valid.
func normalizePassword(password string) []byte {
	raw := []byte(password)
	if len(raw) <= bcryptMaxBytes {
		return raw
	}
	sum := sha256.Sum256(raw)
	return []byte(hex.EncodeToString(sum[:]))
}

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword(normalizePassword(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), normalizePassword(password)) == nil
}
