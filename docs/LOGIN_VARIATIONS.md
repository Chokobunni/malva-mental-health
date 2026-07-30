# Login Variations Assessment - Malva Mental Health App

## Executive Summary

This document assesses additional login methods for the Malva Mental Health application, evaluating their security, user experience, and implementation complexity for a mental health context.

## Current Login Implementation

### ✅ Implemented

1. **Email + Password**
   - bcrypt password hashing
   - Account lockout after 5 failed attempts
   - Password complexity requirements
   - Session invalidation on password change

2. **JWT Authentication**
   - Access token (24h TTL)
   - Refresh token rotation (30-day TTL)
   - Token refresh mechanism

3. **Security Features**
   - Rate limiting (20 requests/minute)
   - Input sanitization
   - SQL injection prevention
   - XSS protection

## Recommended Additional Login Methods

### 1. 🔐 Two-Factor Authentication (2FA) - HIGH PRIORITY

**Why**: Mental health data is extremely sensitive. 2FA adds critical security.

**Methods**:
- **TOTP (Time-based One-Time Password)**
  - Google Authenticator, Authy, Microsoft Authenticator
  - No SMS dependency (more secure)
  - Works offline
  
- **SMS OTP**
  - Fallback option
  - Easier for users without authenticator apps
  - Less secure (SIM swapping risk)

- **Email OTP**
  - Secondary fallback
  - No additional app required

**Implementation**:
```go
// Backend: Generate TOTP secret
func GenerateTOTPSecret() (string, error) {
    secret := make([]byte, 20)
    _, err := rand.Read(secret)
    return base32.StdEncoding.EncodeToString(secret), nil
}

// Backend: Validate TOTP code
func ValidateTOTPCode(secret, code string) bool {
    // Use crypto/totp library
    return totp.Validate(code, secret)
}
```

**Flutter Integration**:
```dart
// Add qr_code_scanner dependency
// Generate QR code for TOTP setup
// Validate 6-digit code input
```

**Effort**: 2-3 days
**Priority**: HIGH - Critical for mental health data

### 2. 🔑 Magic Link (Passwordless) - MEDIUM PRIORITY

**Why**: Reduces password fatigue, easier onboarding for patients.

**Flow**:
1. User enters email
2. System sends magic link to email
3. User clicks link → authenticated
4. Link expires in 15 minutes

**Implementation**:
```go
// Generate magic link token
func GenerateMagicLink(email string) (string, error) {
    token := generateSecureToken(32)
    // Store token with expiry in database
    // Send email with link
    return token, nil
}

// Validate magic link
func ValidateMagicLink(token string) (string, error) {
    // Look up token in database
    // Check expiry
    // Return user ID
}
```

**Security Considerations**:
- One-time use tokens
- Short expiry (15 minutes)
- Rate limiting on magic link requests
- Email verification required

**Effort**: 2-3 days
**Priority**: MEDIUM - Good for patient experience

### 3. 🌐 Social Login (OAuth 2.0) - LOW PRIORITY

**Why**: Convenience for users, but privacy concerns for mental health.

**Providers**:
- Google Sign-In
- Apple Sign-In (required for iOS)
- Facebook Login

**Privacy Concerns**:
- Mental health app should minimize data sharing
- Social providers may track usage
- Users may prefer anonymity

**Recommendation**: 
- **Not recommended** for initial release
- Consider only for non-sensitive features
- If implemented, make optional

**Effort**: 3-5 days per provider
**Priority**: LOW - Privacy concerns outweigh benefits

### 4. 📱 Biometric Authentication - HIGH PRIORITY

**Why**: Convenient and secure for mobile users.

**Methods**:
- Fingerprint
- Face ID
- Windows Hello (desktop)

**Implementation**:
```dart
// Flutter: local_auth package
import 'package:local_auth/local_auth.dart';

final LocalAuthentication auth = LocalAuthentication();

// Check biometric availability
final bool canAuthenticate = await auth.canCheckBiometrics;

// Authenticate
final bool didAuthenticate = await auth.authenticate(
  localizedReason: 'Please authenticate to access Malva',
  options: const AuthenticationOptions(
    stickyAuth: true,
    biometricOnly: false,
  ),
);
```

**Use Cases**:
- Unlock app after background
- Confirm sensitive actions
- Quick re-authentication

**Effort**: 1-2 days
**Priority**: HIGH - Great UX + security

### 5. 🔒 Hardware Security Keys (FIDO2/WebAuthn) - FUTURE

**Why**: Strongest authentication method.

**Methods**:
- YubiKey
- Titan Security Key
- Platform authenticators (Touch ID, Windows Hello)

**Recommendation**: 
- Consider for professional accounts
- Too complex for patient accounts initially

**Effort**: 5-7 days
**Priority**: FUTURE - Consider for v2.0

## Implementation Roadmap

### Phase 1 (Immediate - Week 1-2)

1. **Biometric Authentication**
   - Add `local_auth` package
   - Implement app unlock with biometrics
   - Add biometric toggle in settings

2. **Email Verification**
   - Verify email on registration
   - Resend verification email
   - Mark unverified accounts

### Phase 2 (Short-term - Month 1)

3. **Two-Factor Authentication (2FA)**
   - TOTP setup with QR code
   - Backup codes generation
   - 2FA enforcement for professionals

4. **Magic Link**
   - Generate magic link tokens
   - Email delivery integration
   - Link validation endpoint

### Phase 3 (Medium-term - Quarter 1)

5. **Social Login (Optional)**
   - Google Sign-In
   - Apple Sign-In
   - Privacy-first implementation

6. **Hardware Security Keys**
   - FIDO2/WebAuthn support
   - Professional account protection

## Security Considerations for Mental Health Context

### ✅ Do

1. **Prioritize privacy**
   - Minimize data collection
   - No social login for core features
   - Anonymous options where possible

2. **Implement progressive security**
   - Basic features: email + password
   - Sensitive features: 2FA required
   - Professional accounts: mandatory 2FA

3. **Provide recovery options**
   - Backup codes for 2FA
   - Email recovery
   - Support contact for lockouts

4. **Audit all authentication events**
   - Login attempts
   - Password changes
   - 2FA setup/changes
   - Session management

### ❌ Don't

1. **Don't use SMS as primary 2FA**
   - SIM swapping risk
   - Privacy concerns
   - Use TOTP instead

2. **Don't force social login**
   - Mental health users may want anonymity
   - Social providers track users
   - Make it optional only

3. **Don't store sensitive auth data**
   - No passwords in plain text
   - No 2FA secrets in logs
   - Encrypt all auth tokens

## Technical Dependencies

### Flutter Packages

```yaml
dependencies:
  # Biometric authentication
  local_auth: ^2.1.8
  
  # QR code for 2FA setup
  qr_code_scanner: ^1.0.1
  qr_flutter: ^4.1.0
  
  # Deep linking for magic links
  app_links: ^6.3.2
  
  # Social login (if needed)
  google_sign_in: ^6.2.2
  sign_in_with_apple: ^6.1.2
```

### Go Dependencies

```go
// TOTP generation/validation
go get github.com/pquerna/otp

// Email sending
go get github.com/mailgun/mailgun-go/v4

// FIDO2/WebAuthn
go get github.com/go-webauthn/webauthn
```

## User Experience Recommendations

### Login Screen Design

```
┌─────────────────────────────────────┐
│           Malva Login               │
├─────────────────────────────────────┤
│                                     │
│  [Email_________________________]   │
│  [Password______________________]   │
│                                     │
│  [        Login Button         ]    │
│                                     │
│  ─────────── OR ───────────         │
│                                     │
│  [   Login with Magic Link    ]     │
│  [   Login with Biometrics    ]     │
│                                     │
│  [  Register  ]  [  Forgot?  ]      │
│                                     │
└─────────────────────────────────────┘
```

### Progressive Security Flow

1. **First login**: Email + password
2. **After 24h**: Biometric prompt
3. **Sensitive action**: 2FA verification
4. **New device**: Email verification

## Compliance Considerations

### HIPAA (US)

- Requires strong authentication
- 2FA recommended for PHI access
- Audit trail required

### GDPR (EU)

- Minimize data collection
- Right to erasure
- Consent management

### Mental Health Specific

- Patient privacy paramount
- Anonymous options where possible
- Crisis override procedures

## Conclusion

For a mental health application, the recommended authentication methods are:

1. **Primary**: Email + Password (current) ✅
2. **Secondary**: Biometric (recommended)
3. **Enhanced**: 2FA with TOTP (recommended)
4. **Convenience**: Magic Link (optional)
5. **Avoid**: Social Login (privacy concerns)

The focus should be on **security and privacy** over convenience, given the sensitive nature of mental health data.

## Next Steps

1. Implement biometric authentication (1-2 days)
2. Add email verification (1 day)
3. Implement 2FA with TOTP (2-3 days)
4. Add magic link support (2-3 days)
5. Security audit and testing (2 days)
