# Hermes + FreeLLMAPI

**28 free LLM providers. One OpenAI-compatible endpoint. One AI agent.**

A single installer that sets up [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) (the free-tier LLM aggregator) and creates a dedicated [Hermes Agent](https://hermes-agent.nousresearch.com) profile — so you can use **~4 billion free tokens/month** through Hermes without paying a cent.

## What you get

```
                          ┌──────────────────┐
                          │  Google Gemini   │
                          │  Groq            │
                          │  Mistral         │
                          │  Cloudflare      │
  ┌─────────┐             │  Cerebras        │
  │ Hermes  │─────┐       │  OpenRouter      │    28 free
  │ Agent   │     │       │  NVIDIA NIM      │    provider
  └─────────┘     │       │  HuggingFace     │    tiers
                  │       │  GitHub Models   │
             ┌────▼───┐   │  Cohere          │
             │FreeLLM │──▶│  Zhipu           │
             │API     │   │  OpenCode Zen    │
             │:3001   │   │  ...and more     │
             └────────┘   └──────────────────┘
```

| Item | What it is | Default cost |
|------|-----------|--------------|
| **FreeLLMAPI** | Docker proxy that routes to 28 free LLM tiers via one OpenAI-compatible `/v1` API | Free (self-hosted) |
| **Hermes Agent** | Open-source AI agent (by Nous Research) with tools, memory, skills, and multi-platform | Free (open-source) |
| **Docker** | Auto-installed if missing (macOS DMG, Linux get.docker.com) | Free |
| **Upstream providers** | ~4B tokens/month aggregate from Google, Groq, Mistral, etc. | Free tier |
| **Premium catalog** | Live model feed from freellmapi.co | $19/yr (optional) |

## Quick Install (macOS)

Open **Terminal.app** and run these commands in order.

### 1. Download the installer

```bash
cd ~/Desktop
git clone https://github.com/gmich1/hermes-freellmapi.git
cd hermes-freellmapi
```

Or without git:

```bash
cd ~/Desktop
mkdir -p hermes-freellmapi
cd hermes-freellmapi
curl -fsSL https://raw.githubusercontent.com/gmich1/hermes-freellmapi/main/install.sh -o install.sh
chmod +x install.sh
```

### 2. Run the installer

```bash
./install.sh
```

This installs Hermes (if needed), Docker Desktop (if needed), and starts FreeLLMAPI on port 3001. The FreeLLMAPI dashboard opens in your browser automatically.

### 3. Add provider API keys

Open `http://localhost:3001` in your browser. Create an admin account, then sign up for the free-tier providers you want and paste their API keys into the **Keys** page. The dashboard generates a unified API key — copy it.

### 4. Wire the key into Hermes

```bash
cd ~/Desktop/hermes-freellmapi
./install.sh --configure
```

This auto-discovers your unified key and writes it into the Hermes profile. Done!

### 5. Use Hermes with FreeLLMAPI

The installer sets `freellmapi` as your default profile — both CLI and Desktop pick it up automatically.

**CLI:**

```bash
hermes
```

**Desktop:**

```bash
hermes desktop
```

The installer syncs FreeLLMAPI config to the default profile — the desktop app should pick it up automatically. If a setup wizard appears on first launch, the provider fields will be pre-filled with FreeLLMAPI settings. Subsequent launches open directly with FreeLLMAPI.

Switch back to the original default anytime:

```bash
hermes profile use default
```

### Headless / CI

```bash
cd ~/Desktop/hermes-freellmapi
FREELLMAPI_KEY=freellmapi-abc123 ./install.sh --configure
```

### Linux

Same commands — the installer auto-detects the OS and adjusts accordingly (Docker CE via `get.docker.com` instead of Docker Desktop DMG). Start from step 2 after downloading.

```bash
cd ~
git clone https://github.com/gmich1/hermes-freellmapi.git
cd hermes-freellmapi
chmod +x install.sh
./install.sh
```

## How it works

### Phase 1: Install (3-10 minutes)

The installer checks prerequisites, installs Hermes (if needed), **auto-installs Docker if missing** (macOS DMG or Linux script), pulls the FreeLLMAPI Docker image, starts it on `localhost:3001`, and creates a `freellmapi` Hermes profile.

### Phase 2: Add provider keys (20 minutes, one-time)

You sign up for free-tier accounts at the providers you want, then paste their API keys into the FreeLLMAPI dashboard. The dashboard encrypts them at rest and generates a single unified API key.

**Direct signup links:**

| Provider | Sign up | Free tier |
|----------|---------|-----------|
| [Google Gemini](https://aistudio.google.com/apikey) | Google account | 10 RPM, 1M context |
| [Groq](https://console.groq.com/keys) | Email + phone | 30 RPM, various models |
| [Mistral AI](https://console.mistral.ai/api-keys/) | Google/GitHub | 1B tokens/month |
| [OpenRouter](https://openrouter.ai/keys) | Email + phone | 21 free models |
| [Cloudflare Workers AI](https://dash.cloudflare.com/) | Email | 10K req/day |
| [Cerebras](https://cloud.cerebras.ai/) | Email | Qwen3 235B |
| [GitHub Models](https://github.com/marketplace/models) | GitHub account | GPT-4.1, GPT-4o |
| [HuggingFace](https://hf.co/settings/tokens) | Email | Inference API |
| [NVIDIA NIM](https://build.nvidia.com/) | Email | 40 RPM eval |
| [Cohere](https://dashboard.cohere.com/) | Email | Trial tokens |
| [Zhipu (Z.ai)](https://z.ai/) | Email | GLM-4.x models |
| [OpenCode Zen](https://opencode.ai/zen) | GitHub | DeepSeek V4 Flash |

### Phase 3: Configure (automatic)

```bash
./install.sh --configure
# Auto-starts Docker + FreeLLMAPI if they're stopped
# Auto-discovers your unified API key from the FreeLLMAPI database
# Writes everything into the Hermes profile
# Done!
```

### Phase 4: Use Hermes (CLI or Desktop)

The installer sets `freellmapi` as your default profile so both surfaces pick it up automatically.

```bash
# CLI — uses FreeLLMAPI by default
hermes

# Desktop — same config, same sessions
hermes desktop
```

The installer also syncs FreeLLMAPI config into the **default** profile so the desktop app's first-run wizard sees it pre-filled. If a setup wizard appears, the provider fields will already be populated with FreeLLMAPI settings.

```bash
# Switch back to original default anytime
hermes profile use default

# Check available models via FreeLLMAPI
curl -s http://localhost:3001/v1/models | python3 -m json.tool
```

## Manual configuration

If you already have FreeLLMAPI running, configure Hermes manually:

```bash
# Create a profile
hermes profile create freellmapi \
  --description "FreeLLMAPI-powered Hermes"

# Open the profile config for editing
hermes config edit --profile freellmapi
```

Add to `~/.hermes/profiles/freellmapi/config.yaml`:

```yaml
model:
  default: auto
  base_url: http://localhost:3001/v1
  api_key: "freellmapi-your-unified-key"
agent:
  max_turns: 150
terminal:
  backend: local
  cwd: .
  timeout: 180
```

Note: `model.provider` is deliberately omitted — the `base_url` handles routing directly. The unified API key is available from the FreeLLMAPI dashboard at `http://localhost:3001` → Keys page.

**Or use inline flags for a one-off session:**

```bash
hermes chat \
  --base-url http://localhost:3001/v1 \
  --api-key freellmapi-your-unified-key
```

## What's in the box

```
hermes-freellmapi/
├── install.sh          # The main installer
├── README.md           # This file
└── providers.md        # Full provider signup reference
```

## Requirements

- **Python 3.8+** (for Hermes) — [install](https://python.org)
- **curl** + **openssl** (for the installer)
- **Docker** is auto-installed if missing (macOS/Linux)

## Uninstall

```bash
cd ~/Desktop/hermes-freellmapi
./install.sh --uninstall
```

This stops FreeLLMAPI, removes the Docker container + data, and deletes the Hermes profile. Your default Hermes installation is untouched.

## Configuration

### Env var overrides

All optional — the installer auto-detects everything by default.

| Variable | Default | Description |
|----------|---------|-------------|
| `FREELLMAPI_DIR` | `~/freellmapi` | Install directory |
| `FREELLMAPI_PORT` | `3001` | Dashboard + API port |
| `FREELLMAPI_KEY` | (auto-discover) | Unified API key — skip prompt for headless/CI |
| `HOST_BIND` | `127.0.0.1` | Docker bind address |
| `HERMES_PROFILE` | `freellmapi` | Hermes profile name |

### Entry points

| Command | What it does |
|---------|-------------|
| `./install.sh` | Full install: Hermes → Docker → FreeLLMAPI → profile |
| `./install.sh --configure` | Auto-discover unified key, write to profile, validate |
| `./install.sh --uninstall` | Remove FreeLLMAPI container + data + Hermes profile |
| `./install.sh --help` | Print usage and provider list |

## License

The installer script is MIT. FreeLLMAPI is MIT. Hermes is Apache 2.0 / MIT. Each upstream provider's ToS governs your use of their API.
