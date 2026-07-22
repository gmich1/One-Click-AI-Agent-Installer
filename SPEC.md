# Hermes + FreeLLMAPI Installer — Functional Specification

## Purpose
A single distributable bash script that takes a user from zero to a working Hermes Agent backed by FreeLLMAPI (28 free LLM providers, ~4B tokens/month). One command, no prerequisites beyond curl + Python 3.8+.

---

## Entry Points

| Command | What it does |
|---------|-------------|
| `bash install.sh` | Full install: Hermes → Docker → FreeLLMAPI → Hermes profile |
| `bash install.sh --configure` | Auto-discover unified key from DB, write to profile, validate |
| `bash install.sh --uninstall` | Remove FreeLLMAPI container + data + Hermes profile |
| `bash install.sh --help` | Print usage |

---

## Phase 1: Install Hermes (`install_hermes`)
- Check if `hermes` is in PATH. If yes, skip.
- If not, install via `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`
- Ensure Python 3.8+ is available.
- Add `~/.local/bin` and venv path to current PATH after install.
- Error if install fails.

## Phase 2: Install Docker (`install_docker`)
- Check if `docker` is in PATH. If yes, skip.
- **macOS**: Detect ARM vs Intel. Download `Docker.dmg` from `https://desktop.docker.com/mac/main/{arm64|amd64}/Docker.dmg`. Mount via `hdiutil attach`. Copy `Docker.app` to `/Applications/`. Launch with `open -a Docker`. Wait for CLI binary to appear in the app bundle, then symlink `/Applications/Docker.app/Contents/Resources/bin/docker` to `/usr/local/bin/docker`. Add to PATH for current session.
- **Linux**: Run `curl -fsSL https://get.docker.com | sh`. Add user to `docker` group via `usermod -aG docker`.
- **Other OS**: Die with message to install manually.
- Verify `docker --version` after install.

## Phase 3: Start Docker Daemon (`ensure_docker_running`)
- If `docker info` succeeds, return.
- **macOS**: `open -a Docker`, then loop up to 60 attempts (2s each) polling `docker info`.
- **Linux**: `sudo systemctl start docker` (or `service docker start`), wait 3s, check.
- Die if daemon doesn't start.

## Phase 4: Install FreeLLMAPI (`install_freellmapi`)
- Calls `install_docker` then `ensure_docker_running` (idempotent).
- Create install dir (`~/freellmapi` by default, configurable via `FREELLMAPI_DIR`).
- Generate `ENCRYPTION_KEY` via `openssl rand -hex 32` (or python3/dev/urandom fallback). Write to `.env` with `PORT` (default 3001). Preserve existing `.env` on re-runs.
- Write `docker-compose.yml`:
  - Image: `ghcr.io/tashfeenahmed/freellmapi:latest`
  - Container name: `freellmapi`
  - Restart: `unless-stopped`
  - Port: `${HOST_BIND}:${PORT}:3001` (default 127.0.0.1)
  - Volume: `freellmapi-data:/app/server/data`
  - Healthcheck: Node.js script fetching `/api/ping` (CMD format, per upstream)
- `docker compose pull` (v2 plugin), fallback to `docker-compose pull` (v1 standalone).
- `docker compose up -d`.
- Loop up to 45 attempts (2s each) polling `http://127.0.0.1:$PORT/api/ping`.
- On success: print dashboard URL, open browser with `open` (macOS) or `xdg-open` (Linux).
- Port conflict check via `lsof` before starting.

## Phase 5: Create Hermes Profile (`create_hermes_profile`)
- Create Hermes profile via `hermes profile create freellmapi --description "..."`.
- Write `~/.hermes/profiles/freellmapi/config.yaml`:
  ```yaml
  model:
    default: auto
    base_url: http://localhost:$PORT/v1
    api_key: ""  # placeholder — filled by --configure
  agent:
    max_turns: 150
  terminal:
    backend: local
    cwd: .
    timeout: 180
  ```
  Note: `model.provider` is deliberately omitted — using `model.base_url` + `model.api_key` directly.
- Write `~/.hermes/profiles/freellmapi/.env` (empty, placeholder instructions).

## Phase 6: Configure (`configure_hermes`)
- Run `ensure_freellmapi_running` (reuses install_docker + ensure_docker_running, then starts compose if needed, waits for health).
- **Auto-discover unified API key** from FreeLLMAPI database:
  1. Check `FREELLMAPI_KEY` env var (headless/CI).
  2. Query the SQLite DB directly: `docker exec freellmapi node -e "..."` reads `settings` table where `key = 'unified_api_key'`.
  3. Fallback: check container logs for `Your unified API key:` (older FreeLLMAPI versions).
  4. Interactive prompt if all auto-discovery fails.
- Validate key format: must match `freellmapi[-_]`.
- Write `config.yaml` with `api_key: $UNIFIED_KEY` and `.env` with `OPENAI_BASE_URL` + `OPENAI_API_KEY`.
- Validate key by calling `/v1/models` with the key as Bearer token. Report model count.
- Print success message with usage instructions.

## Phase 7: Uninstall (`uninstall_all`)
- Confirm with user (must type 'yes').
- `cd $INSTALL_DIR && docker compose down -v --remove-orphans` (removes volumes).
- `rm -rf $INSTALL_DIR` (with safety check ensuring path contains "freellmapi").
- `hermes profile delete freellmapi` (or `rm -rf` the profile dir as fallback).

---

## Shared Utilities (DRY)

| Function | Purpose |
|----------|---------|
| `wait_for_freellmapi [max] [sleep]` | Poll `/api/ping` until healthy. Used by install + ensure. |
| `write_hermes_config <key>` | Write `config.yaml` (single source of truth). Called by create + configure. |
| `write_hermes_dotenv <key>` | Write `.env` appropriately (empty or populated). |
| `generate_encryption_key` | Produce 64-char hex via openssl → python3 → /dev/urandom. |
| `_docker_compose` | `docker compose` v2 with fallback to `docker-compose` v1. |

---

## Improvements Over v1

1. **Database-based key discovery** — queries FreeLLMAPI's SQLite DB directly (reliable after any startup, no log dependency).
2. **DRY** — health-check wait loop, config.yaml generation, and .env writing each live in a single function called from multiple phases.
3. **docker-compose v1 fallback** — `_docker_compose` wrapper tries `docker compose` (v2 plugin) then `docker-compose` (v1 standalone).
4. **Headless/CI support** — `FREELLMAPI_KEY` env var skips all discovery + prompt.
5. **Working key validation** — actually calls `/v1/models` with the real Bearer token (v1 used `***`).
6. **Safety** — uninstall requires typing 'yes' (not 'y'), guarded `rm -rf` with path check, `set -euo pipefail`.
7. **macOS improvements** — waits for Docker CLI binary to appear after install, adds to PATH for current session.
8. **Config convention** — omits `model.provider`, uses `model.base_url` + `model.api_key` directly (per Hermes best practice).
9. **Better healthcheck** — uses upstream CMD format (not CMD-SHELL) matching official docker-compose.yml.
10. **Consolidated phases** — Docker install + daemon start are called from both install and configure paths without code duplication.

---

## Env Vars (configurable)

| Env var | Default | Used in |
|---------|---------|---------|
| `FREELLMAPI_DIR` | `~/freellmapi` | Install dir |
| `FREELLMAPI_PORT` | `3001` | Dashboard port |
| `FREELLMAPI_KEY` | (auto-discover) | Unified API key for headless use |
| `HOST_BIND` | `127.0.0.1` | Docker bind address |
| `HERMES_PROFILE` | `freellmapi` | Hermes profile name |
