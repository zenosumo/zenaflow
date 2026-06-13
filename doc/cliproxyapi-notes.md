# CLIProxyAPI Operational Notes

This document captures the working knowledge learned while installing and configuring CLIProxyAPI on the Zenaflow VPS. It is intentionally practical: where files live, which endpoint families CLIProxyAPI supports, how provider configuration maps to upstream URLs, and the mistakes that caused 404/auth failures during setup.

## Current Zenaflow deployment

CLIProxyAPI runs as its own Docker Compose project on the VPS.

Runtime path:

```text
/opt/core/cliproxyapi/
  docker-compose.yml
  config.yaml        # runtime config, API keys, management secret; mode 0600; do not commit
  auths/             # persisted provider OAuth/auth files
  logs/              # CLIProxyAPI logs
```

Repository documentation/planning paths:

```text
/opt/zenaflow/doc/cliproxyapi-notes.md
/opt/zenaflow/plans/cliproxyapi-install.md
```

Installed runtime facts observed during setup:

```text
Image:        eceasy/cli-proxy-api:v7.1.74
Container:    cliproxyapi
Network:      core_core_net
Internal URL: http://cliproxyapi:8317/v1
Host ports:   localhost-only mappings for 8317 and OAuth callback ports
Management:   https://llmproxy.zenaflow.com/management.html behind Cloudflare Zero Trust
```

The config file does not live inside the container image. It is a host bind mount:

```text
/opt/core/cliproxyapi/config.yaml -> /CLIProxyAPI/config.yaml
```

The mount must be writable while using the bundled Web UI to save provider settings, because the Web UI persists changes back to `/CLIProxyAPI/config.yaml`. This still writes through to the host file at `/opt/core/cliproxyapi/config.yaml`; it does not store config in the container layer.

## Secret handling rules

Never commit or paste values from:

```text
/opt/core/cliproxyapi/config.yaml
/opt/core/cliproxyapi/auths/
```

The config contains at least:

- client-facing CLIProxyAPI API keys;
- the management UI secret key;
- provider API keys added through the Web UI;
- provider-specific request headers that may include copied API keys.

When inspecting config, redact values for keys/headers such as:

```text
api-key
secret-key
x-api-key
Authorization
access_token
refresh_token
```

If a provider key is pasted into chat or logs during troubleshooting, rotate it after setup.

## CLIProxyAPI concepts

CLIProxyAPI exposes OpenAI, Claude/Anthropic, Gemini, Codex/OpenAI Responses, Grok, and OpenAI-compatible interfaces. It can route requests to credentials from OAuth files, API-key config sections, or OpenAI-compatible upstreams.

The important distinction is that `base-url` means different things depending on provider type because each executor appends its own protocol path.

### Client-facing API keys

The top-level config key:

```yaml
api-keys:
  - "..."
```

contains keys accepted by CLIProxyAPI clients. These are not upstream provider keys. Internal consumers such as Dify should call CLIProxyAPI with one of these keys.

Example internal base URL for OpenAI-compatible clients:

```text
http://cliproxyapi:8317/v1
```

Example host-local base URL:

```text
http://127.0.0.1:8317/v1
```

### Provider labels, prefixes, names, and aliases

For `openai-compatibility`, the `name` field is CLIProxyAPI-local provider identity/bookkeeping. It is not sent to the upstream as a model name and does not need to match the upstream provider.

The `prefix` field is client-facing routing namespace. If `prefix: zen`, a model alias such as `deepseek-v4-flash-free` is exposed to clients as:

```text
zen/deepseek-v4-flash-free
```

The `models[].name` field is the upstream model ID sent to the upstream provider.

The `models[].alias` field is the client-visible model name before prefixing.

Use the same value for `name` and `alias` unless deliberately creating a short alias or pooling multiple upstream models behind one alias.

## OpenAI-compatible provider configuration

The official config example uses this shape:

```yaml
openai-compatibility:
  - name: "openrouter"
    disabled: false
    prefix: "test"
    base-url: "https://openrouter.ai/api/v1"
    headers:
      X-Custom-Header: "custom-value"
    api-key-entries:
      - api-key: "REDACTED"
        proxy-url: "socks5://proxy.example.com:1080"
    models:
      - name: "moonshotai/kimi-k2:free"
        alias: "kimi-k2"
```

CLIProxyAPI's OpenAI-compatible executor appends:

```text
/chat/completions
```

to `base-url` for chat completion requests.

Therefore a provider whose real endpoint is:

```text
https://example.com/api/v1/chat/completions
```

should be configured with:

```text
base-url: https://example.com/api/v1
```

not the full `/chat/completions` URL.

The model-pull/test UI may call a models endpoint based on `base-url`, effectively:

```text
{base-url}/models
```

So for OpenAI-compatible providers, `base-url` should normally include the provider's `/v1` API prefix if the provider exposes models at `/v1/models`.

## OpenCode Zen through CLIProxyAPI

OpenCode Zen exposes multiple endpoint families. They must not all be put into one CLIProxyAPI provider type.

Live model list was verified from a Mac using:

```bash
curl -sS https://opencode.ai/zen/v1/models \
  -H "Authorization: Bearer YOUR_OPENCODE_ZEN_API_KEY"
```

The endpoint returned models including Claude, Gemini, GPT, Grok, DeepSeek, Qwen, MiniMax, and other free models.

### Zen OpenAI-compatible chat models

Use CLIProxyAPI provider type:

```text
openai-compatibility
```

Use this base URL:

```text
https://opencode.ai/zen/v1
```

Reason: CLIProxyAPI appends `/chat/completions`, producing:

```text
https://opencode.ai/zen/v1/chat/completions
```

Do not use:

```text
https://opencode.ai/zen
https://opencode.ai/zen/v1/chat/completions
```

The first causes CLIProxyAPI to call `/zen/chat/completions`, which 404s. The second causes path doubling.

Recommended starting config:

```yaml
openai-compatibility:
  - name: "opencode-zen-openai"
    prefix: "zen"
    base-url: "https://opencode.ai/zen/v1"
    api-key-entries:
      - api-key: "REDACTED"
    models:
      - name: "deepseek-v4-flash-free"
        alias: "deepseek-v4-flash-free"
```

Start with one model and verify it before adding more.

Candidate OpenAI-compatible Zen models from the live list:

```text
deepseek-v4-pro
deepseek-v4-flash
deepseek-v4-flash-free
mimo-v2.5-free
qwen3.6-plus-free
minimax-m3-free
nemotron-3-ultra-free
north-mini-code-free
grok-build-0.1
```

Use the exact model ID as both `name` and `alias` unless a shorter alias is intentionally desired.

### Zen GPT / OpenAI Responses models

Zen GPT models are documented/observed as part of the OpenAI Responses-style endpoint family, not normal chat-completions routing.

Use a CLIProxyAPI Codex/OpenAI Responses provider if configuring these manually, not `openai-compatibility`.

Base URL principle for the Codex/OpenAI Responses executor:

```text
base-url: https://opencode.ai/zen
```

because the executor appends the `/v1/responses` path.

Candidate GPT/Responses models from the live Zen model list:

```text
gpt-5.5
gpt-5.5-pro
gpt-5.4-mini
gpt-5.4-nano
gpt-5.3-codex-spark
gpt-5.3-codex
gpt-5.2-codex
gpt-5
gpt-5-codex
gpt-5-nano
```

Do not put GPT Responses models into `openai-compatibility` unless direct endpoint testing proves they work on `/v1/chat/completions`.

### Zen Claude / Anthropic Messages models

Zen Claude models use Anthropic Messages-style requests.

Direct endpoint that worked:

```text
https://opencode.ai/zen/v1/messages
```

The direct Messages endpoint did not accept Bearer-only authentication; it returned `Missing API key`. It accepted Anthropic-style headers:

```text
x-api-key: YOUR_OPENCODE_ZEN_API_KEY
anthropic-version: 2023-06-01
```

CLIProxyAPI's Claude executor appends:

```text
/v1/messages?beta=true
```

to `base-url`.

Therefore the Claude/Anthropic provider base URL must be:

```text
https://opencode.ai/zen
```

not:

```text
https://opencode.ai/zen/v1
https://opencode.ai/zen/v1/messages
```

A working direct curl for Zen Messages is:

```bash
curl -sS https://opencode.ai/zen/v1/messages \
  -H "x-api-key: YOUR_OPENCODE_ZEN_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 64,
    "messages": [
      {
        "role": "user",
        "content": "Reply with exactly: opencode zen messages works"
      }
    ]
  }'
```

Zen Claude model candidates from the live list:

```text
claude-fable-5
claude-opus-4-8
claude-opus-4-7
claude-opus-4-5
claude-sonnet-4-6
claude-haiku-4-5
```

Do not configure these under `openai-compatibility`; that makes CLIProxyAPI call `/chat/completions` and returns an OpenCode 404 page.

### Zen Gemini models

Zen's live model list includes Gemini-style models. Treat these as their own endpoint family unless direct testing proves they work through OpenAI-compatible chat completions.

Observed live Zen Gemini model IDs:

```text
gemini-3.5-flash
gemini-3.1-pro
gemini-3-flash
```

## Troubleshooting patterns learned

### 404 HTML from opencode.ai

A large HTML response titled `Not Found | opencode` means the URL path is wrong. It is not a normal model/auth error.

Most common causes:

- full endpoint pasted into `base-url`, causing path doubling;
- missing `/v1` for OpenAI-compatible config;
- using `openai-compatibility` for Claude Messages models;
- using Claude/Anthropic provider settings for OpenAI-compatible models.

### UI says API key not retained

The Web UI may not re-display secret fields after saving. Verify on the VPS by checking the redacted shape of `/opt/core/cliproxyapi/config.yaml`; do not print raw key values.

Example redacted inspection pattern:

```bash
ssh appdev@zenaflow 'cd /opt/core/cliproxyapi && python3 - <<'"'"'PY'"'"'
from pathlib import Path
for line in Path("config.yaml").read_text().splitlines():
    low = line.lower()
    if any(k in low for k in ["api-key", "secret-key", "x-api-key", "authorization", "token"]):
        print(line.split(":", 1)[0] + ": [REDACTED]")
    else:
        print(line)
PY'
```

### Failed to save config: read-only file system

The Web UI writes to `/CLIProxyAPI/config.yaml`. If the bind mount is read-only, saving fails with:

```text
failed to save config: open /CLIProxyAPI/config.yaml: read-only file system
```

For Web UI-based configuration, the Compose mount must be writable:

```yaml
volumes:
  - ./config.yaml:/CLIProxyAPI/config.yaml
```

not:

```yaml
volumes:
  - ./config.yaml:/CLIProxyAPI/config.yaml:ro
```

The file still resides on the host at `/opt/core/cliproxyapi/config.yaml`.

### Pull models button fails

If the pull-models button returns 404 for OpenCode Zen OpenAI-compatible config, check `base-url`:

```text
Correct:   https://opencode.ai/zen/v1
Wrong:     https://opencode.ai/zen
```

If it changes from 404 to Cloudflare `403 error code: 1010`, the URL path is probably correct but OpenCode/Cloudflare is blocking VPS-originated requests. In that case, manually add models from a Mac-verified `/zen/v1/models` response.

### Verify CLIProxyAPI model registration

After saving provider config, verify the model list through CLIProxyAPI:

```bash
ssh appdev@zenaflow '
cd /opt/core/cliproxyapi
python3 - <<'"'"'PY'"'"'
from pathlib import Path
for line in Path("config.yaml").read_text().splitlines():
    low = line.lower()
    if any(k in low for k in ["api-key", "secret-key", "x-api-key", "authorization", "token"]):
        print(line.split(":", 1)[0] + ": [REDACTED]")
    else:
        print(line)
PY
'
```

Then query `/v1/models` with a client-facing CLIProxyAPI API key from `api-keys`. Do not print the key in terminal output or paste it into chat.

Look for the expected prefixed model, for example:

```text
zen/deepseek-v4-flash-free
```

## Reference links

- CLIProxyAPI docs: `https://help.router-for.me/`
- What is CLIProxyAPI: `https://help.router-for.me/introduction/what-is-cliproxyapi.html`
- Basic configuration: `https://help.router-for.me/configuration/basic.html`
- Configuration options: `https://help.router-for.me/configuration/options.html`
- Upstream repository: `https://github.com/router-for-me/CLIProxyAPI`
- Upstream config example: `https://raw.githubusercontent.com/router-for-me/CLIProxyAPI/main/config.example.yaml`
- OpenCode Zen docs: `https://opencode.ai/docs/zen`
