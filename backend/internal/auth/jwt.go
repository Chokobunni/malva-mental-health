package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Manager struct {
	secret []byte
	ttl    time.Duration
}

type Claims struct {
	Subject string `json:"sub"`
	Role    string `json:"role"`
	Expiry  int64  `json:"exp"`
}

func NewManager(secret string) Manager {
	return Manager{secret: []byte(secret), ttl: 24 * time.Hour}
}

func (m Manager) Issue(userID, role string) (string, error) {
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	claims := Claims{
		Subject: userID,
		Role:    role,
		Expiry:  time.Now().Add(m.ttl).Unix(),
	}
	headerBytes, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	claimsBytes, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(headerBytes) + "." +
		base64.RawURLEncoding.EncodeToString(claimsBytes)
	signature := m.sign(unsigned)
	return unsigned + "." + signature, nil
}

func (m Manager) Verify(token string) (Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return Claims{}, errors.New("invalid token format")
	}
	unsigned := parts[0] + "." + parts[1]
	expected := m.sign(unsigned)
	if !hmac.Equal([]byte(parts[2]), []byte(expected)) {
		return Claims{}, errors.New("invalid token signature")
	}
	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return Claims{}, err
	}
	var claims Claims
	if err := json.Unmarshal(claimsBytes, &claims); err != nil {
		return Claims{}, err
	}
	if claims.Subject == "" || claims.Role == "" {
		return Claims{}, errors.New("invalid token claims")
	}
	if time.Now().Unix() > claims.Expiry {
		return Claims{}, errors.New("token expired")
	}
	return claims, nil
}

func (m Manager) BearerClaims(header string) (Claims, error) {
	token, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		return Claims{}, errors.New("missing bearer token")
	}
	return m.Verify(strings.TrimSpace(token))
}

func (m Manager) sign(unsigned string) string {
	mac := hmac.New(sha256.New, m.secret)
	mac.Write([]byte(unsigned))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func RoleAllowed(role string) bool {
	return role == "patient" || role == "professional" || role == "admin"
}

func NormalizeRole(role string) (string, error) {
	role = strings.ToLower(strings.TrimSpace(role))
	if !RoleAllowed(role) {
		return "", fmt.Errorf("unsupported role %q", role)
	}
	return role, nil
}
