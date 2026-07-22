# Provider Signup Reference

Sign up for free-tier accounts at the providers you want to use, then paste their API keys into the FreeLLMAPI dashboard.

## Tier 1: Easy (Google/GitHub login, no phone)

### Google Gemini
- **Signup:** https://aistudio.google.com/apikey
- **Auth:** Google account
- **Free tier:** 10 RPM, 1M context window, Gemini 2.5 Flash / 3.x previews
- **Key location:** API Keys page in Google AI Studio
- **Notes:** Fastest free model available. No phone verification needed.

### OpenCode Zen
- **Signup:** https://opencode.ai/zen
- **Auth:** GitHub account
- **Free tier:** DeepSeek V4 Flash, Nemotron (promo)
- **Key location:** Dashboard after login
- **Notes:** Very easy — GitHub OAuth only.

### GitHub Models
- **Signup:** https://github.com/marketplace/models
- **Auth:** GitHub account
- **Free tier:** GPT-4.1, GPT-4o (rate-limited)
- **Key location:** Settings → Developer settings → Personal access tokens
- **Notes:** Must create a GitHub PAT with `models:read` scope.

### HuggingFace
- **Signup:** https://hf.co/settings/tokens
- **Auth:** Email (or Google/GitHub)
- **Free tier:** Inference API — DeepSeek V4, Kimi K2.6, Qwen3
- **Key location:** Settings → Access Tokens
- **Notes:** Create a "read" token.

## Tier 2: Medium (email verification, some phone)

### Mistral AI
- **Signup:** https://console.mistral.ai/api-keys/
- **Auth:** Google or GitHub OAuth
- **Free tier:** Large 3, Medium 3.5, Codestral, Devstral — **~1B tokens/month total**
- **Key location:** API Keys page in La Plateforme
- **Notes:** Generous free tier. No phone needed if using Google/GitHub auth.

### Cerebras
- **Signup:** https://cloud.cerebras.ai/
- **Auth:** Email
- **Free tier:** Qwen3 235B (very fast inference)
- **Key location:** Cloud dashboard → API Keys
- **Notes:** Fastest hardware, but limited free usage.

### Zhipu (Z.ai)
- **Signup:** https://z.ai/
- **Auth:** Email
- **Free tier:** GLM-4.5, GLM-4.7 Flash
- **Key location:** API Keys section
- **Notes:** Chinese provider. English interface available.

### NVIDIA NIM
- **Signup:** https://build.nvidia.com/
- **Auth:** Email (or Google/GitHub)
- **Free tier:** 40 RPM, eval-only ToS — Nemotron, Llama, Mistral models
- **Key location:** Build.nvidia.com → API
- **Notes:** Rate-limited and eval-only per ToS.

### Cohere
- **Signup:** https://dashboard.cohere.com/
- **Auth:** Email or Google
- **Free tier:** Trial tokens (Command R+, Command-A)
- **Key location:** API Keys page in dashboard
- **Notes:** ToS restricts personal use — see FreeLLMAPI's ToS table.

## Tier 3: Requires phone verification

### Groq
- **Signup:** https://console.groq.com/keys
- **Auth:** Email + phone
- **Free tier:** 30 RPM, Llama 3.3, Llama 4, GPT-OSS, Qwen3
- **Key location:** Console → API Keys
- **Notes:** Very fast inference. Phone SMS verification required.

### OpenRouter
- **Signup:** https://openrouter.ai/keys
- **Auth:** Email + phone (sometimes)
- **Free tier:** 21 free-tier models (varies)
- **Key location:** Keys page
- **Notes:** Access to many models from one key. May require phone.

### Cloudflare Workers AI
- **Signup:** https://dash.cloudflare.com/
- **Auth:** Email
- **Free tier:** 10K requests/day — Kimi K2, GLM-4.7, GPT-OSS, Granite 4
- **Key location:** Workers & Pages → Workers AI → API Tokens
- **Notes:** Requires a Cloudflare account. Free tier is 10K/day across all models.

## Quick reference: FreeLLMAPI platform IDs

When adding keys to the FreeLLMAPI dashboard, use these platform names:

| Platform ID | Signup URL |
|------------|------------|
| `google` | https://aistudio.google.com/apikey |
| `groq` | https://console.groq.com/keys |
| `mistral` | https://console.mistral.ai/api-keys/ |
| `openrouter` | https://openrouter.ai/keys |
| `cloudflare` | https://dash.cloudflare.com/ |
| `cerebras` | https://cloud.cerebras.ai/ |
| `github` | https://github.com/marketplace/models |
| `huggingface` | https://hf.co/settings/tokens |
| `nvidia` | https://build.nvidia.com/ |
| `cohere` | https://dashboard.cohere.com/ |
| `zhipu` / `z.ai` | https://z.ai/ |
| `opencode-zen` | https://opencode.ai/zen |

## Pro tips

1. **Start with Google + Groq + Mistral** — those three cover most use cases.
2. **Add more as you need them** — you don't need all 28 at once.
3. **Use the declarative config** — FreeLLMAPI supports `FREEAPI_CONFIG_JSON` for repeatable setups.
4. **Check rate limits** — FreeLLMAPI tracks RPM/RPD per key and auto-fallovers.
5. **The premium catalog ($19/yr)** — auto-updates model catalog, but the free version updates every 48 hours from a signed feed.
