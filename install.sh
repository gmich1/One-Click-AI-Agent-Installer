#!/usr/bin/env bash
# =============================================================================
# Hermes + FreeLLMAPI — All-in-One Installer (macOS / Linux)
#
# Installs:
#   1. Hermes Agent                   — if not already installed
#   2. Docker (Desktop on macOS, CE on Linux) — if not already installed
#   3. FreeLLMAPI (Docker)           — 28 free LLM providers, ~4B tokens/month
#   4. A dedicated Hermes profile     — configured to use FreeLLMAPI as backend
#
# Usage:
#   ./install.sh                  Full install (Hermes → Docker → FreeLLMAPI → profile)
#   ./install.sh --configure      Auto-discover unified API key + wire up Hermes
#   ./install.sh --uninstall      Remove FreeLLMAPI container, data, and Hermes profile
#   ./install.sh --help           Show this message
#
# Env vars:
#   FREELLMAPI_DIR     Install directory               (default: ~/freellmapi)
#   FREELLMAPI_PORT    Dashboard + API port             (default: 3001)
#   FREELLMAPI_KEY     Unified API key (for headless/CI) (default: auto-discover)
#   HOST_BIND          Docker bind address              (default: 127.0.0.1)
#   HERMES_PROFILE     Hermes profile name              (default: freellmapi)
# =============================================================================

set -euo pipefail

# ── Ensure common Docker paths are in PATH (macOS) ─────────────────────────
# /usr/local/bin holds the docker symlink; Docker.app holds the real binary.
# Non-login shells (e.g. script shebangs) may not inherit these from the
# user's profile, causing "Docker not found" when it's actually installed.
export PATH="/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

# ── Config (env-overridable) ──────────────────────────────────────────────────
INSTALL_DIR="${FREELLMAPI_DIR:-$HOME/freellmapi}"
PORT="${FREELLMAPI_PORT:-3001}"
HOST_BIND="${HOST_BIND:-127.0.0.1}"
HERMES_PROFILE="${HERMES_PROFILE:-freellmapi}"
PROFILE_DIR="$HOME/.hermes/profiles/$HERMES_PROFILE"
API_HEALTH_URL="http://127.0.0.1:$PORT/api/ping"
API_BASE_URL="http://127.0.0.1:$PORT/v1"
DASHBOARD_URL="http://localhost:$PORT"

# Cached on first install — extracted from Docker logs so normal users
# don't have to hunt through console output for the sign-up code.
SETUP_CODE=""

# ── Colors (printf-based — portable across bash, zsh, sh) ─────────────────────
BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[0;32m')"
BLUE="$(printf '\033[0;34m')"
YELLOW="$(printf '\033[1;33m')"
RED="$(printf '\033[0;31m')"
CYAN="$(printf '\033[0;36m')"
NC="$(printf '\033[0m')"

# ── Helpers ───────────────────────────────────────────────────────────────────
say()  { printf "${GREEN}==>${NC} ${BOLD}%s${NC}\n" "$*"; }
info() { printf "${BLUE}  ·${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC}  %s\n" "$*" >&2; }
die()  { printf "${RED}✗${NC}  %s\n" "$*" >&2; exit 1; }
header() {
  printf "\n${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
  printf "${CYAN}║${NC}  ${BOLD}%-48s${NC}${CYAN}║${NC}\n" "$1"
  printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n\n"
}

# ── Docker compose detection ─────────────────────────────────────────────────
# Try `docker compose` (v2 plugin), fall back to `docker-compose` (v1 standalone)
_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    die "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found. Install Docker Desktop or docker-compose."
  fi
}

# ── Show help ─────────────────────────────────────────────────────────────────
show_help() {
  cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║     Hermes + FreeLLMAPI — All-in-One Installer             ║
╚══════════════════════════════════════════════════════════════╝

Installs FreeLLMAPI (28 free LLM providers via Docker) and creates
a dedicated Hermes profile so you can use ~4B free tokens/month.

USAGE:
    ./install.sh                  Full install
    ./install.sh --configure      Wire unified API key into Hermes
    ./install.sh --uninstall      Remove everything
    ./install.sh --help           This message

WHAT IT DOES:
    1. Installs Hermes Agent (if not present)
    2. Installs Docker (macOS DMG or Linux get.docker.com)
    3. Starts FreeLLMAPI via Docker Compose on port 3001
    4. Creates a "freellmapi" Hermes profile
    5. Opens the FreeLLMAPI dashboard in your browser
    6. After --configure: auto-discovers unified key + validates

FREE TIER PROVIDERS (sign up in the dashboard):
    Google Gemini  ·  Groq  ·  Cerebras  ·  Mistral  ·  OpenRouter
    Cloudflare  ·  NVIDIA  ·  GitHub Models  ·  HuggingFace  ·  Cohere
    Zhipu  ·  OpenCode Zen  ·  and more — 28 total providers.

HEADLESS / CI:
    FREELLMAPI_KEY=freellmapi-... ./install.sh --configure

EOF
  exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  SHARED UTILITIES (DRY — called from multiple phases)
# ══════════════════════════════════════════════════════════════════════════════

# ── Wait for FreeLLMAPI's /api/ping to respond ──────────────────────────────
# Args: $1 = max attempts (default 30), $2 = sleep seconds (default 2)
wait_for_freellmapi() {
  local max_attempts="${1:-30}"
  local sleep_secs="${2:-2}"
  local attempt=1

  while (( attempt <= max_attempts )); do
    if curl -fsS "$API_HEALTH_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_secs"
    ((attempt++))
  done
  return 1
}

# ── Write Hermes profile config.yaml (single source of truth) ───────────────
# Args: $1 = api_key (can be empty placeholder)
write_hermes_config() {
  local api_key="${1:-}"
  mkdir -p "$PROFILE_DIR"
  (umask 077 && cat > "$PROFILE_DIR/config.yaml" <<CONFIGEOF
model:
  default: auto
  base_url: $API_BASE_URL
  api_key: "$api_key"
agent:
  max_turns: 150
terminal:
  backend: local
  cwd: .
  timeout: 180
CONFIGEOF
  )
}

# ── Write profile .env ──────────────────────────────────────────────────────
write_hermes_dotenv() {
  local api_key="${1:-}"
  mkdir -p "$PROFILE_DIR"
  if [[ -n "$api_key" ]]; then
    (umask 077 && cat > "$PROFILE_DIR/.env" <<ENVEOF
# FreeLLMAPI Hermes Profile
OPENAI_BASE_URL=$API_BASE_URL
OPENAI_API_KEY=$api_key
ENVEOF
  )
  else
    cat > "$PROFILE_DIR/.env" <<'ENVEOF'
# FreeLLMAPI Hermes Profile
# Run './install.sh --configure' after adding provider keys
# to the FreeLLMAPI dashboard to populate your unified API key.
ENVEOF
  fi
}

# ── Generate a 64-char hex encryption key ───────────────────────────────────
generate_encryption_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets; print(secrets.token_hex(32))'
  else
    od -vN 32 -An -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || \
      die "Cannot generate encryption key. Install openssl, python3, or ensure /dev/urandom is available."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 1: Install Hermes
# ══════════════════════════════════════════════════════════════════════════════

install_hermes() {
  if command -v hermes >/dev/null 2>&1; then
    info "Hermes already installed ($(hermes --version 2>/dev/null | head -1 || echo 'unknown version'))"
    return 0
  fi

  header "Phase 1: Installing Hermes Agent"

  if ! command -v python3 >/dev/null 2>&1; then
    die "Python 3.8+ is required. Install from https://python.org and re-run."
  fi
  local pyver
  pyver="$(python3 -c 'import sys; print(sys.version_info[:2] >= (3,8))' 2>/dev/null || echo 'False')"
  if [[ "$pyver" != "True" ]]; then
    die "Python 3.8+ is required. Current: $(python3 --version 2>&1). Install from https://python.org."
  fi

  say "Installing Hermes Agent via official script..."
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required. Install it and re-run."
  fi

  # --skip-setup: don't launch the interactive hermes setup wizard.
  # We configure Hermes ourselves non-interactively in later phases.
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup || \
    die "Hermes install failed. Try manually: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"

  # Ensure ~/.local/bin is in PATH for this session
  export PATH="$HOME/.local/bin:$HOME/.hermes/hermes-agent/.venv/bin:$PATH"

  if command -v hermes >/dev/null 2>&1; then
    say "Hermes installed ($(hermes --version 2>/dev/null | head -1))"
  else
    die "Hermes installed but 'hermes' command not found. Try: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 2: Install Docker
# ══════════════════════════════════════════════════════════════════════════════

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker already installed ($(docker --version 2>/dev/null))"
    return 0
  fi

  header "Phase 2: Installing Docker"

  local os
  os="$(uname -s)"

  case "$os" in
    Darwin)
      _install_docker_macos
      ;;
    Linux)
      _install_docker_linux
      ;;
    *)
      die "Unsupported OS '$os'. Install Docker manually: https://docs.docker.com/get-docker/"
      ;;
  esac

  # Verify
  if command -v docker >/dev/null 2>&1; then
    say "Docker installed ($(docker --version 2>/dev/null))"
  else
    die "Docker CLI not found after install. Restart your terminal and re-run."
  fi
}

_install_docker_macos() {
  say "Downloading Docker Desktop for macOS..."
  if ! command -v curl >/dev/null 2>&1; then die "curl is required."; fi

  local arch dmg_url tmp_dmg volume
  arch="$(uname -m)"
  case "$arch" in
    arm64)
      info "Detected Apple Silicon chip — downloading arm64 installer."
      dmg_url="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
      ;;
    x86_64|amd64)
      info "Detected Intel chip — downloading amd64 installer."
      dmg_url="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
      ;;
    *)
      die "Unknown architecture '$arch'. Expected arm64 (Apple Silicon) or x86_64 (Intel). Install Docker manually: https://docs.docker.com/get-docker/"
      ;;
  esac

  tmp_dmg="$(mktemp -d)/Docker.dmg"
  info "Downloading Docker Desktop (this may take a few minutes)..."
  curl -#fSL "$dmg_url" -o "$tmp_dmg" || \
    die "Download failed. Install Docker manually: https://docs.docker.com/get-docker/"

  info "Mounting DMG..."
  volume="$(hdiutil attach "$tmp_dmg" -nobrowse | tail -1 | awk '{print $3}')" || \
    die "Failed to mount DMG."

  info "Copying Docker.app to /Applications..."
  cp -R "$volume/Docker.app" /Applications/ 2>/dev/null || {
    hdiutil detach "$volume" >/dev/null 2>&1 || true
    die "Failed to copy Docker.app. Install manually: https://docs.docker.com/get-docker/"
  }

  hdiutil detach "$volume" >/dev/null 2>&1 || true
  rm -rf "$(dirname "$tmp_dmg")"

  # Launch Docker Desktop so it sets up the CLI symlink
  say "Launching Docker Desktop..."
  open -a Docker

  # Wait for Docker Desktop to create its CLI symlink (can take a moment)
  info "Waiting for Docker CLI to become available..."
  for ((i = 1; i <= 30; i++)); do
    if [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
      break
    fi
    sleep 2
  done

  # Symlink the CLI if it isn't already in PATH
  if ! command -v docker >/dev/null 2>&1; then
    if [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
      mkdir -p /usr/local/bin 2>/dev/null || true
      ln -sf /Applications/Docker.app/Contents/Resources/bin/docker /usr/local/bin/docker 2>/dev/null || {
        warn "Could not symlink docker CLI. Add to PATH manually:"
        info '  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"'
      }
      # Also try adding to current PATH
      export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
    fi
  fi
}

_install_docker_linux() {
  say "Installing Docker via get.docker.com..."
  if ! command -v curl >/dev/null 2>&1; then die "curl is required."; fi
  curl -fsSL https://get.docker.com | sh || \
    die "Docker install failed. Try: curl -fsSL https://get.docker.com | sh"

  # Add user to docker group
  if command -v usermod >/dev/null 2>&1; then
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    info "Added $USER to docker group (re-login to use docker without sudo)"
  fi

  # Ensure docker CLI is available
  if ! command -v docker >/dev/null 2>&1; then
    export PATH="/usr/bin:$PATH"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 3: Start Docker Daemon
# ══════════════════════════════════════════════════════════════════════════════

ensure_docker_running() {
  # Quick check — if docker info works, we're good
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  local os max_attempts attempt
  os="$(uname -s)"
  max_attempts=60

  case "$os" in
    Darwin)
      info "Starting Docker Desktop (daemon)..."
      open -a Docker 2>/dev/null || true
      info "Waiting for Docker Engine (this can take 30-60s on first launch)..."
      attempt=1
      while (( attempt <= max_attempts )); do
        if docker info >/dev/null 2>&1; then
          info "Docker Engine ready ($(( attempt * 2 ))s)"
          return 0
        fi
        sleep 2
        ((attempt++))
      done
      die "Docker Engine didn't start after ${max_attempts} attempts. Open Docker Desktop manually, wait for it to finish starting, and re-run."
      ;;
    Linux)
      info "Starting Docker daemon..."
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start docker 2>/dev/null || true
      elif command -v service >/dev/null 2>&1; then
        sudo service docker start 2>/dev/null || true
      fi
      info "Waiting for Docker Engine..."
      attempt=1
      while (( attempt <= max_attempts )); do
        # Use sudo on Linux — group membership from usermod doesn't take effect until re-login
        if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
          info "Docker Engine ready ($(( attempt * 2 ))s)"
          return 0
        fi
        sleep 2
        ((attempt++))
      done
      die "Docker daemon didn't start after ${max_attempts} attempts. Try: sudo systemctl start docker"
      ;;
    *)
      die "Start Docker manually and re-run."
      ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 4: Install FreeLLMAPI
# ══════════════════════════════════════════════════════════════════════════════

install_freellmapi() {
  header "Phase 3: Installing FreeLLMAPI"

  install_docker
  ensure_docker_running

  say "Setting up FreeLLMAPI in $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"

  # ── .env with encryption key ─────────────────────────────────────────────
  if [[ -f "$INSTALL_DIR/.env" ]]; then
    info "Preserving existing .env (encryption key kept)"
  else
    local enc_key
    enc_key="$(generate_encryption_key)"
    (umask 077 && cat > "$INSTALL_DIR/.env" <<ENVEOF
ENCRYPTION_KEY=$enc_key
PORT=$PORT
ENVEOF
    )
    info "Encryption key generated and saved to $INSTALL_DIR/.env"
  fi

  # ── docker-compose.yml ───────────────────────────────────────────────────
  say "Writing docker-compose.yml..."
  cat > "$INSTALL_DIR/docker-compose.yml" <<DOCKEREOF
services:
  freellmapi:
    image: ghcr.io/tashfeenahmed/freellmapi:latest
    container_name: freellmapi
    restart: unless-stopped
    ports:
      - "${HOST_BIND}:${PORT}:3001"
    env_file:
      - .env
    environment:
      NODE_ENV: production
      PORT: "3001"
    volumes:
      - freellmapi-data:/app/server/data
    healthcheck:
      test:
        [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3001/api/ping').then(function(r){if(!r.ok)process.exit(1)}).catch(function(){process.exit(1)})"
        ]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3

volumes:
  freellmapi-data:
DOCKEREOF

  # ── Port conflict check ──────────────────────────────────────────────────
  if command -v lsof >/dev/null 2>&1; then
    # macOS syntax: -iTCP:PORT -sTCP:LISTEN. Linux expects: -i :PORT -s tcp:LISTEN
    if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || \
       lsof -i ":$PORT" -s tcp:LISTEN >/dev/null 2>&1; then
      warn "Port $PORT is already in use."
      info "  Set a different port: FREELLMAPI_PORT=3002 ./install.sh"
      info "  Or see what's listening: lsof -iTCP:$PORT -sTCP:LISTEN"
    fi
  fi

  # ── Pull + start ─────────────────────────────────────────────────────────
  (
    cd "$INSTALL_DIR" || exit 1
    say "Pulling FreeLLMAPI image..."
    _docker_compose pull --quiet 2>/dev/null || _docker_compose pull

    say "Starting FreeLLMAPI container..."
    _docker_compose up -d
  ) || die "Failed to pull or start FreeLLMAPI container. Check: cd $INSTALL_DIR && docker compose ps"

  # ── Wait for healthy ─────────────────────────────────────────────────────
  say "Waiting for FreeLLMAPI to start (first pull may take a minute)..."
  if wait_for_freellmapi 45 2; then
    say "FreeLLMAPI is running!"
    info "Dashboard: $DASHBOARD_URL"
    info "API:       $API_BASE_URL"

    # ── Extract one-time setup code from Docker logs ──────────────────────
    # The dashboard may prompt for this code when accessed from a non-loopback
    # address (Docker port-forwarding often makes localhost appear remote).
    SETUP_CODE="$(docker logs freellmapi 2>/dev/null | grep -m1 'First-run setup code:' | sed 's/.*First-run setup code: *//')"
    if [[ -n "$SETUP_CODE" ]]; then
      info "Setup code: ${CYAN}$SETUP_CODE${NC} (needed if the dashboard prompts for it)"
    fi

    # Open dashboard
    if command -v open >/dev/null 2>&1; then
      open "$DASHBOARD_URL"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$DASHBOARD_URL" 2>/dev/null || true
    fi
  else
    warn "FreeLLMAPI didn't respond after waiting. Check status:"
    info "  cd $INSTALL_DIR && docker compose ps"
    info "  cd $INSTALL_DIR && docker compose logs freellmapi"
    info "Re-run the installer when Docker is ready."
    return 1
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 5: Create Hermes Profile
# ══════════════════════════════════════════════════════════════════════════════

create_hermes_profile() {
  header "Phase 4: Creating Hermes Profile"

  if ! command -v hermes >/dev/null 2>&1; then
    die "Hermes is not installed. Run the full installer first."
  fi

  # Check if profile already exists: try deleting it first (idempotent if
  # absent, cleans up stale registry entries from a prior uninstall), then
  # create fresh.  hermes profile list outputs a table, so we grep for the
  # profile name appearing anywhere in the output (not -Fx whole-line).
  if hermes profile list 2>/dev/null | grep -q "$HERMES_PROFILE"; then
    say "Hermes profile '$HERMES_PROFILE' already exists — re-registering..."
    hermes profile delete -y "$HERMES_PROFILE" 2>/dev/null || true
  fi

  say "Creating Hermes profile: $HERMES_PROFILE"
  hermes profile create "$HERMES_PROFILE" \
    --description "FreeLLMAPI — 28 free LLM providers through a single OpenAI-compatible endpoint" || \
    warn "Could not create profile via CLI. Creating manually..."

  # Ensure the profile directory exists even if CLI creation failed
  mkdir -p "$PROFILE_DIR"

  # Only write config if it doesn't already exist (preserve user's config on re-install)
  if [[ ! -f "$PROFILE_DIR/config.yaml" ]]; then
    say "Writing profile configuration..."
    write_hermes_config ""   # empty key — user runs --configure later
    write_hermes_dotenv ""   # empty .env with instructions
  else
    info "Preserving existing profile config."
  fi

  info "Profile stored at: $PROFILE_DIR"
  info "Switch to it:      hermes --profile $HERMES_PROFILE"
  info "Set as default:    hermes profile use $HERMES_PROFILE"
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 5b: Ensure FreeLLMAPI is running (used by --configure)
# ══════════════════════════════════════════════════════════════════════════════

ensure_freellmapi_running() {
  # Already healthy?
  if curl -fsS "$API_HEALTH_URL" >/dev/null 2>&1; then
    return 0
  fi

  say "FreeLLMAPI isn't running — starting it..."

  install_docker
  ensure_docker_running

  if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    die "No FreeLLMAPI installation found at $INSTALL_DIR. Run the full installer first."
  fi

  info "Starting FreeLLMAPI container..."
  (cd "$INSTALL_DIR" && _docker_compose up -d) || die "Failed to start FreeLLMAPI container. Check: cd $INSTALL_DIR && docker compose ps"

  info "Waiting for FreeLLMAPI to respond..."
  if wait_for_freellmapi 30 2; then
    say "FreeLLMAPI is running!"

    # ── Extract one-time setup code from Docker logs ──────────────────────
    if [[ -z "$SETUP_CODE" ]]; then
      SETUP_CODE="$(docker logs freellmapi 2>/dev/null | grep -m1 'First-run setup code:' | sed 's/.*First-run setup code: *//')"
    fi

    return 0
  else
    die "FreeLLMAPI didn't start. Check: cd $INSTALL_DIR && docker compose logs freellmapi"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 6: Configure (wire unified API key into Hermes profile)
# ══════════════════════════════════════════════════════════════════════════════

configure_hermes() {
  header "Configuring Hermes to Use FreeLLMAPI"

  ensure_freellmapi_running

  if [[ ! -d "$PROFILE_DIR" ]]; then
    die "Hermes profile '$HERMES_PROFILE' doesn't exist. Run the full installer first."
  fi

  # ── Discover unified API key ─────────────────────────────────────────────

  local unified_key=""

  # 1. Explicit env var (headless / CI)
  unified_key="${FREELLMAPI_KEY:-}"

  # 2. Auto-discover from FreeLLMAPI database (reliable, always works)
  if [[ -z "$unified_key" ]]; then
    local db_key
    db_key="$(docker exec freellmapi node -e "
const Database = require('better-sqlite3');
const db = new Database('/app/server/data/freeapi.db');
const row = db.prepare(\"SELECT value FROM settings WHERE key = 'unified_api_key'\").get();
console.log(row ? row.value : '');
" 2>/dev/null)"
    if [[ -n "$db_key" ]]; then
      unified_key="$db_key"
      say "Auto-discovered unified API key from FreeLLMAPI database!"
      info "Key: ${unified_key:0:24}..."
    else
      warn "Database query for unified key failed (FreeLLMAPI may have changed its schema). Falling back to other methods."
    fi
  fi

  # 3. Fallback: check container logs (older FreeLLMAPI versions logged it)
  if [[ -z "$unified_key" ]]; then
    local log_key
    log_key="$(docker logs freellmapi 2>/dev/null | { grep -m1 'Your unified API key:' || true; } | sed 's/.*Your unified API key: *//')"
    if [[ -n "$log_key" ]]; then
      unified_key="$log_key"
      say "Found unified API key in container logs."
    fi
  fi

  # 4. Interactive fallback
  if [[ -z "$unified_key" ]]; then
    echo ""
    echo "  Couldn't auto-discover the key. Find it at:"
    echo "    → $DASHBOARD_URL → Keys page → Unified API Key"
    echo ""
    echo "  Or set it via env var for headless use:"
    echo "    FREELLMAPI_KEY=freellmapi-... ./install.sh --configure"
    echo ""
    printf "${GREEN}==>${NC} ${BOLD}Paste your unified API key:${NC} "
    read -r unified_key

    if [[ -z "$unified_key" ]]; then
      warn "No key entered. Run './install.sh --configure' again when ready."
      return 1
    fi
  fi

  # ── Validate format ──────────────────────────────────────────────────────
  if [[ ! "$unified_key" =~ ^freellmapi[-_] ]]; then
    warn "Key doesn't look like a FreeLLMAPI unified key (should start with 'freellmapi-' or 'freellmapi_')."
    warn "Proceeding anyway — re-run with --configure if it doesn't work."
  fi

  # ── Write config ─────────────────────────────────────────────────────────
  say "Writing unified API key to Hermes profile..."
  write_hermes_config "$unified_key"
  write_hermes_dotenv "$unified_key"

  # ── Validate the key actually works ──────────────────────────────────────
  say "Validating API key..."
  local test_result model_count

  test_result="$(curl -sfS -H "Authorization: Bearer $unified_key" "$API_BASE_URL/models" 2>/dev/null || echo '')"

  if [[ -n "$test_result" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      model_count="$(echo "$test_result" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")"
    else
      model_count="0"
    fi
    if [[ "$model_count" -gt 0 ]]; then
      say "Key validated — $model_count models in catalog."
    else
      info "Key accepted by FreeLLMAPI (model list may populate after adding provider keys)."
    fi

    # Check if any provider keys are actually configured — without them,
    # FreeLLMAPI can't route to any real LLM and chat requests will hang.
    local provider_count
    provider_count="$(docker exec freellmapi node -e "
const Database = require('better-sqlite3');
const db = new Database('/app/server/data/freeapi.db');
const count = db.prepare('SELECT COUNT(*) as c FROM api_keys WHERE enabled = 1').get();
console.log(count ? count.c : 0);
" 2>/dev/null || echo "0")"
    if [[ "$provider_count" -eq 0 ]]; then
      warn "No provider API keys found in FreeLLMAPI — chat requests will hang!"
      info "  Open $DASHBOARD_URL → Keys page → add provider API keys."
      info "  Then re-run './install.sh --configure' to re-validate."
    else
      info "FreeLLMAPI has $provider_count provider key(s) configured."
    fi
  else
    warn "Could not validate key against FreeLLMAPI. Make sure it's running:"
    info "  curl $API_HEALTH_URL"
    info "  curl -H 'Authorization: Bearer YOUR_KEY' $API_BASE_URL/models"
  fi

  # ── Success ──────────────────────────────────────────────────────────────
  say "Hermes is now configured to use FreeLLMAPI!"

  # Set this as the default profile so both CLI and desktop pick it up
  if hermes profile use "$HERMES_PROFILE" 2>/dev/null; then
    info "Set '$HERMES_PROFILE' as the default profile (CLI + Desktop)."
  else
    info "Could not set default profile. Run: hermes profile use $HERMES_PROFILE"
  fi

  # Also sync FreeLLMAPI config into the default profile so the desktop
  # app's first-run wizard sees a configured backend and skips onboarding.
  info "Syncing FreeLLMAPI config to default profile (desktop-ready)..."
  # Use a tool-supporting model by default — agents require function calling.
  # 'auto' is ideal once you have multiple providers; with only one (e.g. Groq),
  # pin a tool-capable model to avoid "1 model lacks tool-calling" errors.
  hermes --profile default config set model.default auto 2>/dev/null || true
  hermes --profile default config set model.base_url "$API_BASE_URL" 2>/dev/null || true
  hermes --profile default config set model.api_key "$unified_key" 2>/dev/null || true
  hermes --profile default config set model.provider "" 2>/dev/null || true

  echo ""
  if [[ "${provider_count:-0}" -eq 0 ]]; then
    warn "IMPORTANT: No provider API keys configured in FreeLLMAPI yet!"
    echo "  Without provider keys, FreeLLMAPI can't route to any LLM."
    echo "  Chat requests will hang or timeout."
    echo ""
    echo "  → Open $DASHBOARD_URL → Keys page"
    echo "  → Sign up for free-tier providers (Google, Groq, etc.)"
    echo "  → Paste their API keys into FreeLLMAPI"
    echo "  → Then your agent will work!"
  else
    echo "  CLI:"
    echo "    hermes                          # uses default (FreeLLMAPI)"
    echo ""
    echo "  Desktop:"
    echo "    hermes desktop                  # opens with FreeLLMAPI configured"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 7: Uninstall
# ══════════════════════════════════════════════════════════════════════════════

uninstall_all() {
  header "Uninstalling FreeLLMAPI + Hermes Profile"

  warn "This will:"
  info "  · Stop and remove FreeLLMAPI container + all data (volume)"
  info "  · Delete $INSTALL_DIR"
  info "  · Delete Hermes profile '$HERMES_PROFILE'"
  info "  · NOT touch Docker or your default Hermes installation"
  echo ""
  printf "${RED}Type 'yes' to confirm:${NC} "
  read -r confirm
  if [[ "$confirm" != "yes" ]]; then
    info "Aborted."
    exit 0
  fi

  # ── Stop + remove FreeLLMAPI ─────────────────────────────────────────────
  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    say "Stopping FreeLLMAPI and removing data..."
    (cd "$INSTALL_DIR" && _docker_compose down -v --remove-orphans 2>/dev/null) || true
    info "FreeLLMAPI stopped."
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    # Safety: ensure we're not nuking something unintended
    if [[ "$INSTALL_DIR" != "/" && "$INSTALL_DIR" != "$HOME" && "$INSTALL_DIR" == *"freellmapi"* ]]; then
      rm -rf "$INSTALL_DIR"
      info "Removed: $INSTALL_DIR"
    else
      warn "Skipping removal of $INSTALL_DIR (safety check failed). Remove manually."
    fi
  fi

  # ── Delete Hermes profile ────────────────────────────────────────────────
  # grep -q (not -Fx): hermes profile list outputs a table, not plain names.
  if command -v hermes >/dev/null 2>&1 && hermes profile list 2>/dev/null | grep -q "$HERMES_PROFILE"; then
    say "Deleting Hermes profile '$HERMES_PROFILE'..."
    hermes profile delete -y "$HERMES_PROFILE" 2>/dev/null || true
  fi
  # Remove profile directory whether registered or not (belt and suspenders)
  if [[ -d "$PROFILE_DIR" ]]; then
    rm -rf "$PROFILE_DIR"
    info "Removed profile directory: $PROFILE_DIR"
  fi

  say "Uninstall complete."
}

# ══════════════════════════════════════════════════════════════════════════════
#  POST-INSTALL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

print_summary() {
  header "Installation Complete!"
  echo ""

  printf "  ${BOLD}FreeLLMAPI${NC} is running at:    ${CYAN}%s${NC}\n" "$DASHBOARD_URL"
  printf "  ${BOLD}Hermes profile${NC} created:     ${CYAN}%s${NC}\n" "$HERMES_PROFILE"
  echo ""

  echo   "  ┌────────────────────────────────────────────────────────────────┐"
  printf "  │ ${BOLD}NEXT STEPS${NC}                                                     │\n"
  echo   "  ├────────────────────────────────────────────────────────────────┤"
  echo   "  │                                                                │"
  printf "  │ ${BOLD}1.${NC} Open dashboard: ${CYAN}%s${NC}                       │\n" "$DASHBOARD_URL"
  if [[ -n "$SETUP_CODE" ]]; then
    printf "  │      Setup code (if prompted): ${CYAN}%s${NC}                      │\n" "$SETUP_CODE"
  fi
  echo   "  │      Create an account (email + password).                     │"
  echo   "  │                                                                │"
  printf "  │ ${BOLD}2.${NC} Sign up for free-tier providers (Google, Groq, etc.)        │\n"
  echo   "  │      and paste their API keys into the FreeLLMAPI Keys page.   │"
  echo   "  │                                                                │"
  printf "  │ ${BOLD}3.${NC} Copy your Unified API Key from the Keys page.               │\n"
  echo   "  │                                                                │"
  printf "  │ ${BOLD}4.${NC} Run: ${GREEN}./install.sh --configure${NC}                               │\n"
  echo   "  │      (This auto-discovers your key and wires up Hermes.)       │"
  echo   "  │                                                                │"
  printf "  │ ${BOLD}5.${NC} Start using Hermes with FreeLLMAPI:                         │\n"
  printf "  │     ${GREEN}hermes --profile %s${NC}                                │\n" "$HERMES_PROFILE"
  echo   "  │                                                                │"
  echo   "  └────────────────────────────────────────────────────────────────┘"
  echo ""

  printf "  ${BOLD}Headless / CI:${NC}\n"
  echo   "    FREELLMAPI_KEY=freellmapi-... ./install.sh --configure"
  echo   ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
  # Check minimum requirements upfront
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required. Install it and re-run."
  fi

  local mode="${1:-install}"

  case "$mode" in
    --help|-h|help)
      show_help
      ;;
    --configure|-c|configure)
      configure_hermes
      ;;
    --uninstall|--remove|-u|uninstall)
      uninstall_all
      ;;
    *)
      # Reject unknown flags; no-arg triggers full install
      if [[ "${1:-}" == -* ]]; then
        die "Unknown option: $1. Use --help to see usage."
      fi
      header "Hermes + FreeLLMAPI Installer"
      cat <<'EOF'
  Installs FreeLLMAPI (28 free LLM providers via Docker) and creates
  a dedicated Hermes profile. ~4 billion free tokens/month.

EOF
      install_hermes
      install_freellmapi
      create_hermes_profile
      print_summary
      ;;
  esac
}

main "$@"
