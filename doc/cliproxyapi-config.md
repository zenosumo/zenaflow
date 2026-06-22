# CLIProxyAPI Current Configuration

This document records the current Zenaflow CLIProxyAPI configuration and the model names exposed to downstream services. It is a redacted operational snapshot generated from the live VPS configuration; the source of truth remains `/opt/core/cliproxyapi/config.yaml`, `/opt/core/cliproxyapi/auths/`, and the authenticated `/v1/models` endpoint.

For service mechanics, deployment paths, secret handling, and provider semantics, see `doc/cliproxyapi-notes.md`.

Last verified: 2026-06-22 19:49 UTC

## Management interface

The management UI is available at:

```text
https://llmproxy.zenaflow.com/management.html
```

Access layers:

```text
Cloudflare Zero Trust -> Caddy -> 127.0.0.1:8317 -> CLIProxyAPI management UI
```

The UI requires the CLIProxyAPI management key. The active config stores `remote-management.secret-key` as a bcrypt hash after startup; if the plaintext is unknown, reset it or retrieve it from a known backup. Do not paste the bcrypt hash into the UI.

Current remote-management flags:

```text
allow-remote: true
disable-control-panel: false
```

## Service endpoints for downstream apps

Use these endpoints from other Zenaflow services:

```text
Internal Docker-network base URL: http://cliproxyapi:8317/v1
Host-local base URL:             http://127.0.0.1:8317/v1
Models endpoint:                 /models
Chat completions endpoint:       /chat/completions
```

For OpenAI-compatible downstream services such as Dify, RAGFlow, Open WebUI, or workflow apps:

```text
Provider type: OpenAI-compatible
Base URL:      http://cliproxyapi:8317/v1
API key:       a top-level CLIProxyAPI client key from /opt/core/cliproxyapi/config.yaml -> api-keys
Model:         one of the exposed model names below, e.g. gpt-big, claude-sonnet, gemini-3.1-pro
```

Current client API key count: 1

Do not put upstream provider keys or OAuth tokens into downstream services. Downstream services should only receive CLIProxyAPI client-facing API keys.

## Routing policy

Current critical setting:

```yaml
force-model-prefix: false
```

This is intentional. It means:

- unprefixed aliases such as `gpt-big` and `gemini-3.1-pro` can use the highest-priority eligible source first and then lower-priority eligible sources when appropriate;
- prefixed aliases such as `sub/gpt-big`, `api/gemini-3.1-pro`, and `zen/gpt-big` force a specific source;
- prefixes do not need to be removed for the desired “default alias plus explicit provider route” behavior.

Priority order currently used:

```text
100  subscription/OAuth accounts (`sub` prefix)
20   direct Gemini API key (`api` prefix)
10   OpenCode Zen (`zen` prefix)
```

## Provider sources

Configured provider/source families:

```text
sub/*  OAuth/subscription accounts
api/*  direct Google Gemini API key
zen/*  OpenCode Zen through OpenAI-compatible provider
```

OAuth/subscription auth files:

```text
claude  priority 100 prefix sub disabled false claude-zenotempo@gmail.com.json
codex   priority 100 prefix sub disabled false codex-zenotempo@gmail.com-plus.json
gemini  priority 100 prefix sub disabled false gemini-zenosumo@gmail.com-gen-lang-client-0955546592.json
```

Direct API-key provider:

```text
gemini-api-key  priority 20  prefix api  disabled not set
base URL: https://generativelanguage.googleapis.com/v1beta/openai/
models: gemini-3.1-pro -> gemini-3.1-pro-preview, gemini-3.5-flash
```

OpenAI-compatible provider:

```text
name: opencode-zen
priority: 10
prefix: zen
disabled: not set
base URL: https://opencode.ai/zen/v1
API-key entries: 1
models: claude-fable -> claude-fable-5, claude-opus -> claude-opus-4-8, claude-sonnet -> claude-sonnet-4-6, claude-haiku -> claude-haiku-4-5, gemini-3.5-flash, gemini-3.1-pro, gpt-big -> gpt-5.5, gpt-5.5-pro, gpt-5.4-mini, gpt-5.4-nano, gpt-5.3-codex-spark, gpt-5.3-codex, grok-build-0.1, deepseek-v4-pro
```

## Recommended default model names

Use these unprefixed names in normal downstream apps when you want the configured default/priority route:

```text
gpt-big
claude-opus
claude-sonnet
claude-fable
claude-haiku
gemini-3.1-pro
gemini-3-flash
gemini-3.1-flash-lite
gemini-3.5-flash
```

Practical defaults:

```text
gpt-big                 default large GPT/Codex route
claude-opus             strongest Claude-style route
claude-sonnet           balanced Claude-style coding/reasoning route
claude-fable            alternate Claude-style route
claude-haiku            lightweight Claude-style route
gemini-3.1-pro          Gemini Pro route
gemini-3-flash          fast Gemini route
gemini-3.1-flash-lite   lightweight Gemini route
gemini-3.5-flash        Gemini Flash route
```

## Explicit source prefixes

Use prefixed aliases when you want to force a source instead of relying on the default route:

```text
sub/<alias>  force subscription/OAuth
api/<alias>  force direct API-key source
zen/<alias>  force OpenCode Zen
```

Examples:

```text
sub/gpt-big              force Codex/OpenAI OAuth subscription
zen/gpt-big              force OpenCode Zen GPT route
sub/claude-sonnet        force Claude OAuth subscription
zen/claude-sonnet        force OpenCode Zen Claude route
sub/gemini-3.1-pro       force Gemini CLI OAuth subscription
api/gemini-3.1-pro       force direct Gemini API key
zen/gemini-3.1-pro       force OpenCode Zen Gemini route
```

## Exposed model names

Authenticated `/v1/models` currently returns 59 model names:

```text
api/gemini-3.1-pro
api/gemini-3.5-flash
claude-fable
claude-fable-5
claude-haiku
claude-haiku-4-5-20251001
claude-opus
claude-opus-4-8
claude-sonnet
claude-sonnet-4-6
codex-auto-review
deepseek-v4-pro
gemini-3-flash
gemini-3-flash-preview
gemini-3.1-flash-lite
gemini-3.1-flash-lite-preview
gemini-3.1-pro
gemini-3.1-pro-preview
gemini-3.5-flash
gpt-5.3-codex
gpt-5.3-codex-spark
gpt-5.4-mini
gpt-5.4-nano
gpt-5.5-pro
gpt-big
gpt-image-2
grok-build-0.1
sub/claude-fable
sub/claude-fable-5
sub/claude-haiku-4-5-20251001
sub/claude-opus
sub/claude-opus-4-8
sub/claude-sonnet
sub/claude-sonnet-4-6
sub/codex-auto-review
sub/gemini-3-flash
sub/gemini-3-flash-preview
sub/gemini-3.1-flash-lite
sub/gemini-3.1-flash-lite-preview
sub/gemini-3.1-pro
sub/gemini-3.1-pro-preview
sub/gpt-5.3-codex-spark
sub/gpt-5.4-mini
sub/gpt-big
sub/gpt-image-2
zen/claude-fable
zen/claude-haiku
zen/claude-opus
zen/claude-sonnet
zen/deepseek-v4-pro
zen/gemini-3.1-pro
zen/gemini-3.5-flash
zen/gpt-5.3-codex
zen/gpt-5.3-codex-spark
zen/gpt-5.4-mini
zen/gpt-5.4-nano
zen/gpt-5.5-pro
zen/gpt-big
zen/grok-build-0.1
```

## Alias/source matrix from live `/v1/models`

This matrix groups exposed model names by base name after removing the known `sub/`, `api/`, and `zen/` prefixes. It shows what clients can request; the unprefixed route remains governed by CLIProxyAPI provider priority and availability.

```text

claude-fable
  sub/claude-fable
  zen/claude-fable
  claude-fable
claude-fable-5
  sub/claude-fable-5
  claude-fable-5
claude-haiku
  zen/claude-haiku
  claude-haiku
claude-haiku-4-5-20251001
  sub/claude-haiku-4-5-20251001
  claude-haiku-4-5-20251001
claude-opus
  sub/claude-opus
  zen/claude-opus
  claude-opus
claude-opus-4-8
  sub/claude-opus-4-8
  claude-opus-4-8
claude-sonnet
  sub/claude-sonnet
  zen/claude-sonnet
  claude-sonnet
claude-sonnet-4-6
  sub/claude-sonnet-4-6
  claude-sonnet-4-6
codex-auto-review
  sub/codex-auto-review
  codex-auto-review
deepseek-v4-pro
  zen/deepseek-v4-pro
  deepseek-v4-pro
gemini-3-flash
  sub/gemini-3-flash
  gemini-3-flash
gemini-3-flash-preview
  sub/gemini-3-flash-preview
  gemini-3-flash-preview
gemini-3.1-flash-lite
  sub/gemini-3.1-flash-lite
  gemini-3.1-flash-lite
gemini-3.1-flash-lite-preview
  sub/gemini-3.1-flash-lite-preview
  gemini-3.1-flash-lite-preview
gemini-3.1-pro
  sub/gemini-3.1-pro
  api/gemini-3.1-pro
  zen/gemini-3.1-pro
  gemini-3.1-pro
gemini-3.1-pro-preview
  sub/gemini-3.1-pro-preview
  gemini-3.1-pro-preview
gemini-3.5-flash
  api/gemini-3.5-flash
  zen/gemini-3.5-flash
  gemini-3.5-flash
gpt-5.3-codex
  zen/gpt-5.3-codex
  gpt-5.3-codex
gpt-5.3-codex-spark
  sub/gpt-5.3-codex-spark
  zen/gpt-5.3-codex-spark
  gpt-5.3-codex-spark
gpt-5.4-mini
  sub/gpt-5.4-mini
  zen/gpt-5.4-mini
  gpt-5.4-mini
gpt-5.4-nano
  zen/gpt-5.4-nano
  gpt-5.4-nano
gpt-5.5-pro
  zen/gpt-5.5-pro
  gpt-5.5-pro
gpt-big
  sub/gpt-big
  zen/gpt-big
  gpt-big
gpt-image-2
  sub/gpt-image-2
  gpt-image-2
grok-build-0.1
  zen/grok-build-0.1
  grok-build-0.1

```

## OAuth model aliases

Configured global OAuth aliases:

```text

[claude]
  claude-opus -> claude-opus-4-8  fork true
  claude-fable -> claude-fable-5  fork true
  claude-sonnet -> claude-sonnet-4-6  fork true
[gemini-cli]
  gemini-3.1-pro -> gemini-3.1-pro-preview  fork true
  gemini-3.1-flash-lite -> gemini-3.1-flash-lite-preview  fork true
  gemini-3-flash -> gemini-3-flash-preview  fork true
[codex]
  gpt-big -> gpt-5.5

```

`fork: true` means the alias is added as an additional client-visible model rather than only renaming/replacing the upstream name in listings.

## Excluded OAuth models

The config intentionally excludes some upstream OAuth models from listings/routing to reduce clutter or avoid undesired variants.

```text

[claude]
  claude-sonnet-4-5-20250929
  claude-opus-4-6
  claude-opus-4-7
  claude-opus-4-5-20251101
  claude-opus-4-1-20250805
  claude-opus-4-20250514
  claude-sonnet-4-20250514
  claude-3-7-sonnet-20250219
  claude-3-5-haiku-20241022
[gemini-cli]
  gemini-2.5-pro
  gemini-2.5-flash
  gemini-2.5-flash-lite
  gemini-3-pro-preview
[codex]
  gpt-5.4

```

## Dify / app setup examples

Default route for GPT-big:

```text
Provider type: OpenAI-compatible
Base URL:      http://cliproxyapi:8317/v1
API key:       <CLIProxyAPI client API key from api-keys>
Model:         gpt-big
```

Force a specific source if needed:

```text
Model: sub/gpt-big   # force Codex/OpenAI subscription
Model: zen/gpt-big   # force OpenCode Zen
```

Force direct Gemini API key:

```text
Model: api/gemini-3.1-pro
```

## Verification snapshot

Checks performed from the VPS:

```text
Container status: cliproxyapi running
Local authenticated /v1/models: 59 models
Dify plugin_daemon -> http://cliproxyapi:8317/v1/models: reachable, 59 models
Smoke test: POST /v1/chat/completions model=gpt-big -> http 200; model gpt-5.5; response content CLIP_OK
```

Re-check model list with:

```bash
cd /opt/core/cliproxyapi
KEY=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('config.yaml'))
print(cfg['api-keys'][0])
PY
)
curl -sS -H "$(printf '%s: %s %s' Authorization Bearer "$KEY")" http://127.0.0.1:8317/v1/models
```
