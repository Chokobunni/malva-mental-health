# Security Hardening Guide - Malva Mental Health App

## Executive Summary

This document provides comprehensive security hardening guidelines for the Malva Mental Health application, covering backend, frontend, database, and infrastructure security measures.

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                          │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Network Security (TLS, CORS, CSP)                │
│  Layer 2: Authentication (JWT, bcrypt, 2FA)                │
│  Layer 3: Authorization (RBAC, Consent)                    │
│  Layer 4: Input Validation (Sanitization, Injection)       │
│  Layer 5: Data Protection (Encryption, Masking)            │
│  Layer 6: Audit & Monitoring (Logging, Alerts)             │
└─────────────────────────────────────────────────────────────┘
```

## 1. Backend Security (Go)

### 1.1 Authentication

#### JWT Configuration
```go
// Current implementation
- Algorithm: HS256
- Access Token TTL: 24 hours
- Refresh Token TTL: 30 days
- Secret: 64-character random string
```

#### Password Security
```go
// Implemented
- Hashing: bcrypt (cost factor 12)
- Minimum length: 8 characters
- Complexity: uppercase, lowercase, digit, special char
- Account lockout: 5 attempts, 15-minute lockout
- Common password rejection
```

#### Session Management
```go
// Implemented
- Refresh token rotation
- Session invalidation on password change
- Device-specific sessions
- IP tracking
```

### 1.2 Input Validation

#### SQL Injection Prevention
```go
// Implemented in security/sanitization.go
- Parameterized queries
- Input pattern detection
- Request size limits (1MB)
- Path traversal detection
```

#### XSS Prevention
```go
// Implemented
- HTML entity encoding
- Script tag removal
- Event handler removal
- Content Security Policy headers
```

#### Request Validation
```go
// Implemented
- JSON schema validation
- Field length limits
- Type checking
- Enum validation
```

### 1.3 Rate Limiting

#### Current Configuration
```go
// server.go
- Login: 20 requests/minute per IP
- Registration: 20 requests/minute per IP
- API endpoints: 20 requests/minute per IP
- WebSocket: Connection limits
```

#### Recommended Enhancements
```go
// Additional rate limiting
- Per-user rate limiting
- Sliding window algorithm
- Redis-based distributed limiting
- Exponential backoff
```

### 1.4 Security Headers

#### Implemented Headers
```go
// server.go
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: no-referrer
Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

#### Additional Recommendations
```go
// Additional headers
X-Permitted-Cross-Domain-Policies: none
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
```

### 1.5 CORS Configuration

#### Current Configuration
```go
// config.go
AllowedOrigins: ["http://localhost:3000", "http://localhost:5173", "http://localhost:8080"]
AllowedMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
AllowedHeaders: ["Authorization", "Content-Type", "X-CSRF-Token"]
AllowCredentials: true
MaxAge: 86400
```

#### Production Recommendations
```go
// Production CORS
- Whitelist specific production domains
- Disable wildcard origins
- Restrict methods to required only
- Log CORS violations
```

## 2. Frontend Security (Flutter)

### 2.1 Secure Storage

#### Token Storage
```dart
// Implemented
- flutter_secure_storage for tokens
- EncryptedSharedPreferences on Android
- Keychain on iOS
- No tokens in SharedPreferences
```

#### Sensitive Data
```dart
// Recommendations
- Never log sensitive data
- Clear sensitive data from memory
- Use secure clipboard handling
- Disable screenshots in sensitive screens
```

### 2.2 Network Security

#### Certificate Pinning
```dart
// Recommended implementation
class CertificatePinner {
  static const _pins = [
    'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  ];
  
  static bool validate(X509Certificate cert) {
    // Validate certificate chain
    return true;
  }
}
```

#### Request Security
```dart
// Implemented
- HTTPS only in production
- Token refresh mechanism
- Request timeout handling
- Error message sanitization
```

### 2.3 Biometric Authentication

#### Implementation
```dart
// Recommended
import 'package:local_auth/local_auth.dart';

class BiometricAuth {
  final _auth = LocalAuthentication();
  
  Future<bool> authenticate() async {
    return await _auth.authenticate(
      localizedReason: 'Authenticate to access Malva',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
      ),
    );
  }
}
```

### 2.4 Code Obfuscation

#### Build Configuration
```bash
# Release builds
flutter build apk --obfuscate --split-debug-info=build/debug-info
flutter build ios --obfuscate --split-debug-info=build/debug-info
```

## 3. Database Security (PostgreSQL)

### 3.1 Access Control

#### User Permissions
```sql
-- Current setup
CREATE USER malva WITH PASSWORD 'malva_dev_password';
GRANT CONNECT ON DATABASE malva TO malva;
GRANT USAGE ON SCHEMA public TO malva;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO malva;

-- Production recommendations
CREATE USER malva_readonly WITH PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE malva TO malva_readonly;
GRANT USAGE ON SCHEMA public TO malva_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO malva_readonly;
```

#### Connection Security
```sql
-- PostgreSQL configuration
ssl = on
ssl_cert_file = '/path/to/server.crt'
ssl_key_file = '/path/to/server.key'
ssl_ca_file = '/path/to/ca.crt'
password_encryption = scram-sha-256
```

### 3.2 Data Encryption

#### At Rest
```sql
-- Enable TDE (Transparent Data Encryption)
-- Or use filesystem-level encryption
ALTER SYSTEM SET data_encryption = on;
```

#### In Transit
```go
// Connection string with SSL
"postgres://user:pass@host:5432/dbname?sslmode=verify-full"
```

### 3.3 Audit Logging

#### PostgreSQL Audit
```sql
-- Enable pgaudit extension
CREATE EXTENSION pgaudit;

-- Configure audit logging
ALTER SYSTEM SET pgaudit.log = 'all';
ALTER SYSTEM SET pgaudit.log_catalog = on;
ALTER SYSTEM SET pgaudit.log_level = 'log';
```

### 3.4 Backup Security

#### Encrypted Backups
```bash
# Backup with encryption
pg_dump malva | gzip | gpg --encrypt --recipient admin@malva.app > backup.sql.gz.gpg

# Restore
gpg --decrypt backup.sql.gz.gpg | gunzip | psql malva
```

## 4. Infrastructure Security

### 4.1 Network Security

#### Firewall Rules
```bash
# Allow only required ports
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP (redirect to HTTPS)
ufw allow 443/tcp   # HTTPS
ufw allow 8080/tcp  # API (if needed)
ufw deny all
```

#### Load Balancer
```nginx
# Nginx configuration
server {
    listen 443 ssl http2;
    server_name api.malva.app;
    
    ssl_certificate /etc/ssl/certs/malva.crt;
    ssl_certificate_key /etc/ssl/private/malva.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 4.2 Docker Security

#### Dockerfile Best Practices
```dockerfile
# Use non-root user
RUN addgroup -S malva && adduser -S malva -G malva
USER malva

# Read-only filesystem
RUN chmod -R 555 /app

# No new privileges
--security-opt no-new-privileges:true
```

#### Container Scanning
```bash
# Scan for vulnerabilities
trivy image malva-api:latest
grype malva-api:latest
```

### 4.3 Secret Management

#### Environment Variables
```bash
# Never commit secrets
echo "*.env" >> .gitignore
echo "*.pem" >> .gitignore
echo "*.key" >> .gitignore

# Use secret management
export MALVA_JWT_SECRET=$(aws secretsmanager get-secret-value --secret-id malva-jwt-secret)
export MALVA_DATABASE_URL=$(aws secretsmanager get-secret-value --secret-id malva-db-url)
```

## 5. Monitoring & Incident Response

### 5.1 Security Monitoring

#### Log Aggregation
```go
// Implemented
- Structured JSON logging
- Security event logging
- Authentication logging
- Authorization logging
```

#### Alert Rules
```yaml
# Prometheus alerts
groups:
  - name: security
    rules:
      - alert: HighFailedLogins
        expr: rate(auth_failures_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: High rate of failed logins
          
      - alert: AccountLockout
        expr: increase(account_lockouts_total[1h]) > 5
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: Multiple account lockouts detected
```

### 5.2 Incident Response

#### Response Plan
1. **Detection**: Monitor logs and alerts
2. **Containment**: Isolate affected systems
3. **Eradication**: Remove threat
4. **Recovery**: Restore services
5. **Lessons Learned**: Document and improve

#### Emergency Contacts
```yaml
contacts:
  security_lead: security@malva.app
  devops: devops@malva.app
  legal: legal@malva.app
```

## 6. Compliance

### 6.1 HIPAA Compliance

#### Required Measures
- [x] Access controls
- [x] Audit logging
- [x] Data encryption
- [x] Transmission security
- [x] Integrity controls
- [x] Authentication
- [x] Emergency access
- [ ] Business continuity (TODO)
- [ ] Disaster recovery (TODO)

### 6.2 GDPR Compliance

#### Required Measures
- [x] Data minimization
- [x] Consent management
- [x] Right to access
- [x] Right to erasure
- [x] Data portability
- [x] Privacy by design
- [ ] Data protection officer (TODO)
- [ ] Impact assessment (TODO)

### 6.2 OWASP Top 10 Mitigation

| Vulnerability | Status | Mitigation |
|--------------|--------|------------|
| A01: Broken Access Control | ✅ | RBAC, consent, audit |
| A02: Cryptographic Failures | ✅ | bcrypt, JWT, TLS |
| A03: Injection | ✅ | Parameterized queries |
| A04: Insecure Design | ✅ | Security review |
| A05: Security Misconfiguration | ✅ | Security headers |
| A06: Vulnerable Components | ⚠️ | Dependency scanning |
| A07: Auth Failures | ✅ | 2FA, lockout |
| A08: Data Integrity Failures | ✅ | Input validation |
| A09: Logging Failures | ✅ | Audit logging |
| A10: SSRF | ✅ | Input validation |

## 7. Security Checklist

### Pre-Production

- [ ] All secrets rotated
- [ ] SSL/TLS configured
- [ ] Security headers enabled
- [ ] Rate limiting configured
- [ ] Input validation complete
- [ ] SQL injection prevented
- [ ] XSS prevention enabled
- [ ] CSRF protection enabled
- [ ] Account lockout configured
- [ ] Password policy enforced
- [ ] Audit logging enabled
- [ ] Backup encryption enabled
- [ ] Incident response plan documented
- [ ] Security training completed

### Post-Production

- [ ] Regular security audits
- [ ] Dependency updates
- [ ] Penetration testing
- [ ] Vulnerability scanning
- [ ] Log monitoring
- [ ] Incident response drills
- [ ] Compliance audits
- [ ] Security awareness training

## 8. Security Tools

### Recommended Tools

| Category | Tool | Purpose |
|----------|------|---------|
| SAST | SonarQube | Static analysis |
| DAST | OWASP ZAP | Dynamic testing |
| SCA | Snyk | Dependency scanning |
| Container | Trivy | Image scanning |
| Secrets | HashiCorp Vault | Secret management |
| Monitoring | Prometheus | Metrics |
| Logging | ELK Stack | Log aggregation |
| IDS | Suricata | Intrusion detection |

## 9. Emergency Procedures

### Security Incident Response

```bash
# 1. Immediate response
- Isolate affected systems
- Preserve evidence
- Notify security team

# 2. Investigation
- Review audit logs
- Identify scope
- Document findings

# 3. Remediation
- Patch vulnerabilities
- Rotate credentials
- Update security controls

# 4. Recovery
- Restore from backups
- Verify integrity
- Monitor closely

# 5. Post-incident
- Document lessons
- Update procedures
- Train team
```

### Credential Rotation

```bash
# Rotate JWT secret
export MALVA_JWT_SECRET=$(openssl rand -hex 32)

# Rotate database password
psql -c "ALTER USER malva WITH PASSWORD '$(openssl rand -hex 16)';"

# Rotate API keys
# Update all clients
# Invalidate old keys
```

## 10. Regular Security Tasks

### Daily
- Review security logs
- Monitor failed login attempts
- Check system health

### Weekly
- Review audit logs
- Update dependencies
- Security scan

### Monthly
- Penetration testing
- Compliance review
- Security training

### Quarterly
- Full security audit
- Policy review
- Incident response drill

## Resources

- [OWASP Security Guidelines](https://owasp.org/www-project-web-security-testing-guide/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [GDPR Documentation](https://gdpr.eu/)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
- [Flutter Security](https://flutter.dev/docs/reference/security)
