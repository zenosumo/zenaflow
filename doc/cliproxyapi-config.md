# CLIProxyAPI Current Configuration

This document records the current Zenaflow CLIProxyAPI configuration and how to use the configured aliases. It is a redacted operational snapshot; the live source of truth remains `/opt/core/cliproxyapi/config.yaml` and `/opt/core/cliproxyapi/auths/` on the VPS.

For service mechanics, deployment paths, secret handling, and provider semantics, see `doc/cliproxyapi-notes.md`.

## Management interface

The management UI is available at:

```text
https://llmproxy.zenaflow.com/management.html
```

Access layers:

```text
Cloudflare Zero Trust -> Caddy -> 127.0.0.1:8317 -> CLIProxyAPI management UI
```

The UI also requires the CLIProxyAPI management secret from `/opt/core/cliproxyapi/config.yaml`.

## Service endpoints

Use these endpoints from other Zenaflow services:

```text
Internal Docker-network base URL: http://cliproxyapi:8317/v1
Host-local base URL:             http://127.0.0.1:8317/v1
Models endpoint:                 /models
Chat completions endpoint:       /chat/completions
```

For an OpenAI-compatible downstream service such as Dify, RAGFlow, Open WebUI, or another workflow app:

```text
Provider type: OpenAI-compatible
Base URL:      http://cliproxyapi:8317/v1
API key:       a top-level CLIProxyAPI client key from /opt/core/cliproxyapi/config.yaml
Model:         one of the aliases below, e.g. gpt-big, claude-sonnet, gemini-3.1-pro
```

Do not put upstream provider keys or OAuth tokens into downstream services. Use only CLIProxyAPI client-facing API keys.

## Routing policy

Current critical setting:

```yaml
force-model-prefix: false
```

This is intentional. It means:

- unprefixed aliases such as `gpt-big` and `gemini-3.1-pro` can use the highest-priority eligible source first and then try lower-priority eligible sources when appropriate;
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
claude  priority 100  prefix sub  auths/claude-zenotempo@gmail.com.json
codex   priority 100  prefix sub  auths/codex-zenotempo@gmail.com-plus.json
gemini  priority 100  prefix sub  auths/gemini-zenosumo@gmail.com-gen-lang-client-0955546592.json
```

Direct API-key provider:

```text
gemini-api-key  priority 20  prefix api
base URL: https://generativelanguage.googleapis.com/v1beta/openai/
```

OpenCode Zen provider:

```text
openai-compatibility provider name: opencode-zen
priority: 10
prefix: zen
base URL: https://opencode.ai/zen/v1
```

## Default aliases

Use these unprefixed aliases in normal downstream apps when you want the configured priority order to pick the preferred source first:

```text
gpt-big
gemini-3.1-pro
gemini-3-flash
gemini-3.1-flash-lite
claude-opus
claude-sonnet
claude-fable
```

Practical default choices:

```text
gpt-big                 default large GPT/Codex route
claude-opus             strongest Claude-style route
claude-sonnet           balanced Claude-style route
gemini-3.1-pro          Gemini Pro route
gemini-3-flash          fast Gemini route
gemini-3.1-flash-lite   lightweight Gemini route
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

## Alias matrix

Aliases with multiple configured sources:

```text
gemini-3.1-pro
  gemini-3.1-pro           priority 100  Gemini CLI OAuth/subscription -> gemini-3.1-pro-preview
  sub/gemini-3.1-pro       priority 100  force Gemini CLI OAuth/subscription -> gemini-3.1-pro-preview
  api/gemini-3.1-pro       priority 20   force direct Gemini API key -> gemini-3.1-pro-preview
  zen/gemini-3.1-pro       priority 10   force OpenCode Zen -> gemini-3.1-pro

claude-fable
  claude-fable             priority 100  Claude OAuth/subscription -> claude-fable-5
  sub/claude-fable         priority 100  force Claude OAuth/subscription -> claude-fable-5
  zen/claude-fable         priority 10   force OpenCode Zen -> claude-fable-5

claude-opus
  claude-opus              priority 100  Claude OAuth/subscription -> claude-opus-4-8
  sub/claude-opus          priority 100  force Claude OAuth/subscription -> claude-opus-4-8
  zen/claude-opus          priority 10   force OpenCode Zen -> claude-opus-4-8

claude-sonnet
  claude-sonnet            priority 100  Claude OAuth/subscription -> claude-sonnet-4-6
  sub/claude-sonnet        priority 100  force Claude OAuth/subscription -> claude-sonnet-4-6
  zen/claude-sonnet        priority 10   force OpenCode Zen -> claude-sonnet-4-6

gpt-big
  gpt-big                  priority 100  Codex/OpenAI OAuth/subscription -> gpt-5.5
  sub/gpt-big              priority 100  force Codex/OpenAI OAuth/subscription -> gpt-5.5
  zen/gpt-big              priority 10   force OpenCode Zen -> gpt-5.5

gemini-3-flash
  gemini-3-flash           priority 100  Gemini CLI OAuth/subscription -> gemini-3-flash-preview
  sub/gemini-3-flash       priority 100  force Gemini CLI OAuth/subscription -> gemini-3-flash-preview

gemini-3.1-flash-lite
  gemini-3.1-flash-lite    priority 100  Gemini CLI OAuth/subscription -> gemini-3.1-flash-lite-preview
  sub/gemini-3.1-flash-lite priority 100 force Gemini CLI OAuth/subscription -> gemini-3.1-flash-lite-preview

gemini-3.5-flash
  api/gemini-3.5-flash     priority 20   force direct Gemini API key -> gemini-3.5-flash
  zen/gemini-3.5-flash     priority 10   force OpenCode Zen -> gemini-3.5-flash
```

Aliases currently only on Zen/OpenCode or another single source:

```text
zen/claude-haiku          -> claude-haiku-4-5
zen/gpt-5.5-pro           -> gpt-5.5-pro
zen/gpt-5.4-mini          -> gpt-5.4-mini
zen/gpt-5.4-nano          -> gpt-5.4-nano
zen/gpt-5.3-codex-spark   -> gpt-5.3-codex-spark
zen/gpt-5.3-codex         -> gpt-5.3-codex
zen/grok-build-0.1        -> grok-build-0.1
zen/deepseek-v4-pro       -> deepseek-v4-pro
api/gemini-3.5-flash      -> gemini-3.5-flash
```

## OAuth model aliases

Configured global OAuth aliases:

```text
claude-opus    -> claude-opus-4-8      fork true
claude-fable   -> claude-fable-5       fork true
claude-sonnet  -> claude-sonnet-4-6    fork true

gemini-3.1-pro         -> gemini-3.1-pro-preview          fork true
gemini-3.1-flash-lite  -> gemini-3.1-flash-lite-preview   fork true
gemini-3-flash         -> gemini-3-flash-preview          fork true

gpt-big        -> gpt-5.5
```

`fork: true` means the alias is added as an additional client-visible model rather than only renaming/replacing the upstream name in listings.

## Model choice guidance

Use unprefixed aliases for normal app configuration:

```text
gpt-big        best default GPT/Codex-style route
claude-opus    strongest Claude-style reasoning route
claude-sonnet  balanced Claude-style coding/reasoning route
gemini-3.1-pro Gemini Pro route
gemini-3-flash fast Gemini route
```

Use prefixed aliases for diagnostics, cost/source control, or manual fallback:

```text
sub/...  test or force subscription/OAuth
api/...  test or force direct Google API billing
zen/...  test or force OpenCode Zen
```

Example downstream app settings:

```text
Base URL: http://cliproxyapi:8317/v1
API Key:  <CLIProxyAPI client key>
Model:    gpt-big
```

To force OpenCode Zen for the same conceptual model:

```text
Model: zen/gpt-big
```

To force direct Gemini API key:

```text
Model: api/gemini-3.1-pro
```

## Excluded OAuth models

The config intentionally excludes some upstream OAuth models from listings/routing to reduce clutter or avoid undesired variants.

Claude exclusions include:

```text
claude-sonnet-4-5-20250929
claude-opus-4-6
claude-opus-4-7
claude-opus-4-5-20251101
claude-opus-4-1-20250805
claude-opus-4-20250514
claude-sonnet-4-20250514
claude-3-7-sonnet-20250219
claude-3-5-haiku-20241022
```

Gemini CLI exclusions include:

```text
gemini-2.5-pro
gemini-2.5-flash
gemini-2.5-flash-lite
gemini-3-pro-preview
```

Codex exclusions include:

```text
gpt-5.4
```

## Verification snapshot

The live `/v1/models` endpoint was observed returning the configured aliases, including:

```text
gpt-big
sub/gpt-big
zen/gpt-big
claude-opus
sub/claude-opus
zen/claude-opus
claude-sonnet
sub/claude-sonnet
zen/claude-sonnet
gemini-3.1-pro
sub/gemini-3.1-pro
api/gemini-3.1-pro
zen/gemini-3.1-pro
api/gemini-3.5-flash
zen/gemini-3.5-flash
```

Re-check with:

```bash
cd /opt/core/cliproxyapi
KEY=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('config.yaml'))
print(cfg['api-keys'][0])
PY
)
curl -sS -H "Authorization: Bearer <CLIProxyAPI-client-key>" http://127.0.0.1:8317/v1/models
```
