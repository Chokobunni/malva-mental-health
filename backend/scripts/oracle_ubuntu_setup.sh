#!/usr/bin/env bash
set -Eeuo pipefail

MALVA_DOMAIN="${MALVA_DOMAIN:-}"
MALVA_REPO_URL="${MALVA_REPO_URL:-}"
MALVA_BRANCH="${MALVA_BRANCH:-main}"
MALVA_APP_DIR="${MALVA_APP_DIR:-/opt/malva/app}"
MALVA_USER="${MALVA_USER:-malva}"
MALVA_DB_NAME="${MALVA_DB_NAME:-malva}"
MALVA_DB_USER="${MALVA_DB_USER:-malva}"
MALVA_DB_PASSWORD="${MALVA_DB_PASSWORD:-}"
MALVA_JWT_SECRET="${MALVA_JWT_SECRET:-}"
MALVA_ALLOWED_ORIGINS="${MALVA_ALLOWED_ORIGINS:-}"
MALVA_GO_VERSION="${MALVA_GO_VERSION:-1.26.5}"
MALVA_FCM_CREDENTIALS_FILE="${MALVA_FCM_CREDENTIALS_FILE:-/etc/malva/firebase-service-account.json}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
  fi
}

random_hex() {
  openssl rand -hex "$1"
}

psql_escape_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

version_at_least() {
  local current="$1"
  local required="$2"
  [[ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]
}

detect_arch() {
  case "$(uname -m)" in
    aarch64|arm64) echo "arm64" ;;
    x86_64|amd64) echo "amd64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_go_if_needed() {
  local arch
  arch="$(detect_arch)"

  if command -v go >/dev/null 2>&1; then
    local current
    current="$(go version | awk '{print $3}' | sed 's/^go//')"
    if version_at_least "$current" "1.23"; then
      echo "Go $current already installed."
      return
    fi
  fi

  local tarball="/tmp/go${MALVA_GO_VERSION}.linux-${arch}.tar.gz"
  echo "Installing Go ${MALVA_GO_VERSION} for linux-${arch}..."
  curl -fsSL "https://go.dev/dl/go${MALVA_GO_VERSION}.linux-${arch}.tar.gz" -o "$tarball"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tarball"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
}

prepare_source() {
  mkdir -p "$(dirname "$MALVA_APP_DIR")"

  if [[ -f "./backend/go.mod" ]]; then
    local current_dir
    current_dir="$(pwd)"
    if [[ "$current_dir" != "$MALVA_APP_DIR" ]]; then
      mkdir -p "$MALVA_APP_DIR"
      rsync -a --delete \
        --exclude ".git" \
        --exclude "build" \
        --exclude ".dart_tool" \
        --exclude "android/app/google-services.json" \
        "$current_dir"/ "$MALVA_APP_DIR"/
    fi
    return
  fi

  if [[ -n "$MALVA_REPO_URL" ]]; then
    if [[ -d "$MALVA_APP_DIR/.git" ]]; then
      git -C "$MALVA_APP_DIR" fetch origin "$MALVA_BRANCH"
      git -C "$MALVA_APP_DIR" checkout "$MALVA_BRANCH"
      git -C "$MALVA_APP_DIR" pull --ff-only origin "$MALVA_BRANCH"
    else
      git clone --branch "$MALVA_BRANCH" "$MALVA_REPO_URL" "$MALVA_APP_DIR"
    fi
    return
  fi

  echo "Project source not found. Run from repo root or set MALVA_REPO_URL." >&2
  exit 1
}

configure_postgres() {
  systemctl enable --now postgresql

  local escaped_password
  escaped_password="$(psql_escape_literal "$MALVA_DB_PASSWORD")"

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${MALVA_DB_USER}'" | grep -q 1; then
    sudo -u postgres createuser "$MALVA_DB_USER"
  fi

  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER \"${MALVA_DB_USER}\" WITH PASSWORD '${escaped_password}'"

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${MALVA_DB_NAME}'" | grep -q 1; then
    sudo -u postgres createdb -O "$MALVA_DB_USER" "$MALVA_DB_NAME"
  fi

  apply_migrations
}

apply_migrations() {
  sudo -u postgres psql -d "$MALVA_DB_NAME" -v ON_ERROR_STOP=1 -c "
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  "

  if sudo -u postgres psql -d "$MALVA_DB_NAME" -tAc "SELECT to_regclass('public.users')" | grep -q "users"; then
    sudo -u postgres psql -d "$MALVA_DB_NAME" -v ON_ERROR_STOP=1 -c "
      INSERT INTO schema_migrations (version)
      VALUES ('001_initial.sql')
      ON CONFLICT (version) DO NOTHING
    "
  fi

  local migration
  for migration in "$MALVA_APP_DIR"/backend/migrations/*.sql; do
    local version
    version="$(basename "$migration")"
    if sudo -u postgres psql -d "$MALVA_DB_NAME" -tAc "SELECT 1 FROM schema_migrations WHERE version='${version}'" | grep -q 1; then
      echo "Migration ${version} already applied."
      continue
    fi
    echo "Applying migration ${version}..."
    sudo -u postgres psql -d "$MALVA_DB_NAME" -v ON_ERROR_STOP=1 -f "$migration"
    sudo -u postgres psql -d "$MALVA_DB_NAME" -v ON_ERROR_STOP=1 -c "
      INSERT INTO schema_migrations (version)
      VALUES ('${version}')
    "
  done
}

build_backend() {
  cd "$MALVA_APP_DIR/backend"
  go mod download
  go test ./...
  go build -trimpath -buildvcs=false -ldflags="-s -w" -o /tmp/malva-api ./cmd/api
  install -o root -g root -m 0755 /tmp/malva-api /usr/local/bin/malva-api
}

write_environment() {
  mkdir -p /etc/malva
  chmod 750 /etc/malva

  local allowed_origins="$MALVA_ALLOWED_ORIGINS"
  if [[ -z "$allowed_origins" && -n "$MALVA_DOMAIN" ]]; then
    allowed_origins="https://${MALVA_DOMAIN}"
  fi
  if [[ -z "$allowed_origins" ]]; then
    allowed_origins="http://localhost:8080"
  fi

  local fcm_credentials_file=""
  if [[ -f "$MALVA_FCM_CREDENTIALS_FILE" ]]; then
    fcm_credentials_file="$MALVA_FCM_CREDENTIALS_FILE"
  else
    echo "FCM service account not found at ${MALVA_FCM_CREDENTIALS_FILE}; backend will use no-op notification provider until configured."
  fi

  cat > /etc/malva/malva-api.env <<EOF_ENV
MALVA_HTTP_ADDR=127.0.0.1:8080
MALVA_DATABASE_URL=postgres://${MALVA_DB_USER}:${MALVA_DB_PASSWORD}@127.0.0.1:5432/${MALVA_DB_NAME}?sslmode=disable
MALVA_JWT_SECRET=${MALVA_JWT_SECRET}
MALVA_ALLOWED_ORIGINS=${allowed_origins}
MALVA_FCM_CREDENTIALS_FILE=${fcm_credentials_file}
MALVA_FCM_CREDENTIALS_JSON=
EOF_ENV

  chown root:"$MALVA_USER" /etc/malva/malva-api.env
  chmod 640 /etc/malva/malva-api.env
}

install_systemd_service() {
  install -o root -g root -m 0644 "$MALVA_APP_DIR/backend/deploy/systemd/malva-api.service" /etc/systemd/system/malva-api.service
  systemctl daemon-reload
  systemctl enable --now malva-api
  systemctl restart malva-api
}

configure_caddy() {
  if [[ -z "$MALVA_DOMAIN" ]]; then
    echo "MALVA_DOMAIN not set; skipping public HTTPS Caddy config."
    return
  fi

  cat > /etc/caddy/Caddyfile <<EOF_CADDY
${MALVA_DOMAIN} {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080
}
EOF_CADDY

  systemctl enable --now caddy
  systemctl reload caddy
}

configure_firewall() {
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
}

main() {
  require_root

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl git jq openssl postgresql postgresql-contrib rsync caddy ufw

  install_go_if_needed

  if ! id "$MALVA_USER" >/dev/null 2>&1; then
    useradd --system --home /opt/malva --shell /usr/sbin/nologin "$MALVA_USER"
  fi

  MALVA_DB_PASSWORD="${MALVA_DB_PASSWORD:-$(random_hex 32)}"
  MALVA_JWT_SECRET="${MALVA_JWT_SECRET:-$(random_hex 48)}"

  prepare_source
  mkdir -p /var/backups/malva
  chown "$MALVA_USER":"$MALVA_USER" /var/backups/malva

  configure_postgres
  build_backend
  write_environment
  install_systemd_service
  configure_caddy
  configure_firewall

  curl -fsS http://127.0.0.1:8080/healthz
  echo
  echo "Malva backend is installed."
  echo "Environment: /etc/malva/malva-api.env"
  echo "Service: systemctl status malva-api --no-pager"
  if [[ -n "$MALVA_DOMAIN" ]]; then
    echo "Public health check: https://${MALVA_DOMAIN}/healthz"
  fi
}

main "$@"
