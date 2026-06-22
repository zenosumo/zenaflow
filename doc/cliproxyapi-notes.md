# CLIProxyAPI Technical Notes

This document captures how CLIProxyAPI works on Zenaflow at the service/operational level. Keep the live, user-facing model aliases and provider choices in `doc/cliproxyapi-config.md` instead.

## Service role

CLIProxyAPI is Zenaflow's internal LLM proxy. It provides OpenAI-compatible, Gemini-compatible, Claude/Anthropic-compatible, Codex/OpenAI Responses, and other API surfaces backed by OAuth/subscription accounts, direct API keys, and OpenAI-compatible upstream providers.

Use it when a Zenaflow service needs an LLM provider but should not talk directly to each upstream account/provider.

## Deployment shape

Runtime path on the VPS:

```text
/opt/core/cliproxyapi/
  docker-compose.yml
  config.yaml        # runtime config, API keys, management secret; mode 0600; do not commit
  auths/             # persisted provider OAuth/auth files
  logs/              # CLIProxyAPI logs
```

Repository documentation paths:

```text
/opt/zenaflow/doc/cliproxyapi-notes.md   # this technical/service note
/opt/zenaflow/doc/cliproxyapi-config.md  # current live Zenaflow configuration and aliases
/opt/zenaflow/plans/cliproxyapi-install.md
```

Runtime service facts:

```text
Container:    cliproxyapi
Compose dir:  /opt/core/cliproxyapi
Network:      core_core_net
Internal URL: http://cliproxyapi:8317/v1
Host URL:     http://127.0.0.1:8317/v1
UI path:      /management.html
Host ports:   localhost-only mappings for 8317 and OAuth callback ports
```

The config file is a host bind mount:

```text
/opt/core/cliproxyapi/config.yaml -> /CLIProxyAPI/config.yaml
```

The mount must be writable while using the bundled Web UI because the UI saves provider/API-key changes by writing `/CLIProxyAPI/config.yaml`. That still writes through to the host file; it does not store config in the container layer.

## Public management access

The management UI is available at:

```text
https://llmproxy.zenaflow.com/management.html
```

The hostname is routed through Caddy to `127.0.0.1:8317` and should remain protected by Cloudflare Zero Trust. CLIProxyAPI also has its own management secret in `config.yaml`; both layers matter.

Local/tunnel access is also possible:

```bash
ssh -L 8317:127.0.0.1:8317 appdev@zenaflow
```

Then open:

```text
http://127.0.0.1:8317/management.html
```

## OAuth callback ports

Provider OAuth flows redirect the user's browser to localhost callback ports. When the browser is on the user's Mac and CLIProxyAPI runs on the VPS, open an SSH tunnel before starting a fresh OAuth flow.

Full setup tunnel:

```bash
ssh \
  -L 8317:127.0.0.1:8317 \
  -L 8085:127.0.0.1:8085 \
  -L 1455:127.0.0.1:1455 \
  -L 54545:127.0.0.1:54545 \
  -L 51121:127.0.0.1:51121 \
  -L 11451:127.0.0.1:11451 \
  appdev@zenaflow
```

Known callback ports:

```text
8317   management UI/API
8085   Gemini login/callback auxiliary server
1455   Codex/OpenAI OAuth callback
54545  Claude Code callback
51121  Antigravity callback
11451  iFlow callback
```

Do not reuse old callback URLs/codes after a failed attempt. Start the OAuth flow fresh once the tunnel is open.

## Secret handling

Never commit or paste raw values from:

```text
/opt/core/cliproxyapi/config.yaml
/opt/core/cliproxyapi/auths/
```

These files contain client API keys, the management secret, upstream provider API keys, OAuth access/refresh tokens, and custom headers such as `x-api-key`.

When inspecting or documenting config, redact:

```text
api-key
secret-key
x-api-key
Authorization
access_token
refresh_token
token
```

If a provider key is pasted into chat/logs during troubleshooting, rotate it afterward.

## Provider model routing concepts

CLIProxyAPI model routing has four separate concepts:

- `models[].name` is the upstream model ID sent to the selected provider.
- `models[].alias` is the client-visible model name before prefixing.
- `prefix` is a client-visible namespace used to force a provider/credential route, e.g. `zen/gpt-big`.
- `priority` chooses among eligible credentials/providers for a requested model; higher priority wins first.

The important setting is:

```yaml
force-model-prefix: false
```

With `force-model-prefix: false`, unprefixed requests may use prefixed credentials/providers, and prefixed names still force a specific source. This supports the desired pattern:

```text
gpt-big      -> default/priority-routed model
sub/gpt-big  -> force subscription/OAuth source
api/...      -> force direct API-key source
zen/...      -> force OpenCode Zen source
```

If `force-model-prefix: true`, unprefixed model requests only use credentials without a prefix, except when prefix equals the model name. That would prevent the current “unprefixed default with prefixed force routes” design.

## OpenAI-compatible upstreams

For `openai-compatibility`, the provider `name` is CLIProxyAPI-local identity/bookkeeping; it is not the upstream model name.

The OpenAI-compatible executor appends:

```text
/chat/completions
```

to `base-url`. Therefore a provider whose real endpoint is:

```text
https://example.com/api/v1/chat/completions
```

should be configured with:

```text
base-url: https://example.com/api/v1
```

not the full `/chat/completions` URL.

The Web UI model-pull/test flow may probe:

```text
{base-url}/models
```

So OpenAI-compatible `base-url` usually includes the provider's `/v1` API prefix if its models endpoint is `/v1/models`.

## OpenCode Zen endpoint families

OpenCode Zen exposes multiple endpoint families. Do not assume one CLIProxyAPI provider type covers all protocol families.

For Zen OpenAI-compatible chat models, use CLIProxyAPI `openai-compatibility` with:

```text
base-url: https://opencode.ai/zen/v1
```

CLIProxyAPI then calls:

```text
https://opencode.ai/zen/v1/chat/completions
```

Do not configure these as the base URL:

```text
https://opencode.ai/zen
https://opencode.ai/zen/v1/chat/completions
```

The first produces `/zen/chat/completions`; the second doubles the path.

For Zen Claude/Anthropic Messages-style integrations, if using CLIProxyAPI's Claude API-key provider, the source appends `/v1/messages?beta=true`, so the base URL should be the service root, not `/v1/messages`. OpenCode Zen Messages also requires Anthropic-style headers (`x-api-key` and `anthropic-version`) for direct Messages calls.

## Using CLIProxyAPI from other services

For services on `core_core_net`, use:

```text
Base URL: http://cliproxyapi:8317/v1
API key:  one of the top-level client API keys from /opt/core/cliproxyapi/config.yaml
Model:    one of the aliases in doc/cliproxyapi-config.md
```

For host-local checks on the VPS:

```text
Base URL: http://127.0.0.1:8317/v1
```

For typical OpenAI-compatible clients, configure:

```text
OpenAI-compatible base URL: http://cliproxyapi:8317/v1
Chat completions endpoint:  /chat/completions
Models endpoint:            /models
Authorization:              Bearer <CLIProxyAPI client API key>
```

Do not use upstream provider API keys in downstream services. Downstream services should only receive CLIProxyAPI client-facing keys.

## Verification commands

Run from the VPS:

```bash
cd /opt/core/cliproxyapi
docker compose ps
```

Authenticated model list, redacting the client key in output:

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

Public UI should be Cloudflare Access protected for unauthenticated callers:

```bash
curl -sS -D - -o /tmp/llmproxy_probe.html --max-redirs 0 https://llmproxy.zenaflow.com/management.html
```

Expected public unauthenticated behavior is a Cloudflare Access `302`, not the raw CLIProxyAPI management HTML.
