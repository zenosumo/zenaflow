# Secure n8n webhook ingress on Cloudflare

## Scope

This plan secures `n8n-in.zenaflow.com`, the public n8n webhook ingress hostname, at the Cloudflare edge while preserving `n8n.zenaflow.com` as the private human editor/admin UI behind Cloudflare Zero Trust GitHub login.

The desired end state is:

- `n8n.zenaflow.com` remains the browser UI hostname for humans and stays protected by Cloudflare Access/GitHub login.
- `n8n-in.zenaflow.com` remains the machine/webhook ingress hostname and is not protected by normal browser-login Access unless all intended callers can authenticate non-interactively.
- Cloudflare blocks non-webhook paths before traffic reaches the VPS.
- Caddy on the VPS remains the origin-side backstop that only passes public n8n webhook/form paths to `127.0.0.1:5678`.
- Real workflows still authenticate callers at the workflow level with a bearer token, HMAC signature, secret query token, or Cloudflare Access service token where possible.

## Why this matters

`n8n-in.zenaflow.com` is intentionally internet-facing. That is necessary for external services to call n8n webhooks, but it also creates an attack surface. Without Cloudflare edge restrictions, scanners and abusive clients can reach the VPS and probe n8n routes, trigger expensive workflow paths, create noise in logs, and consume CPU/RAM on a resource-constrained server.

The n8n editor and webhook ingress have different trust models:

- The editor UI is for a human in a browser and should require interactive identity login.
- Webhooks are for machines and usually cannot complete a GitHub/Zero Trust browser login.

Keeping those hostnames separate makes the security model explicit and avoids accidentally breaking webhooks while protecting the admin UI.

## Plan

- Confirm the current hostname roles before changing Cloudflare.
  - What to check:
    - `n8n.zenaflow.com` is the editor/admin UI hostname.
    - `n8n-in.zenaflow.com` is the canonical generated webhook ingress hostname.
    - `webhook.n8n.zenaflow.com`, if still present, is only a compatibility/testing hostname and should not be the long-term canonical hostname unless Cloudflare edge certificate coverage is deliberately added for the nested name.
  - Why:
    - Cloudflare Universal SSL normally covers flat names like `*.zenaflow.com`, including `n8n-in.zenaflow.com`, but not necessarily nested names like `*.n8n.zenaflow.com`.
    - Confirming roles first prevents applying a browser Access policy to the webhook hostname and accidentally breaking external callers.
  - How:
    - In Cloudflare DNS, verify `n8n-in.zenaflow.com` exists and is proxied/orange-clouded.
    - In Cloudflare Zero Trust Access, verify the existing application for `n8n.zenaflow.com` still points only at the editor hostname.
    - From outside the VPS, test current behavior with `curl -I https://n8n.zenaflow.com/` and `curl -I https://n8n-in.zenaflow.com/`.

- Leave the existing Cloudflare Access GitHub login policy for `n8n.zenaflow.com` in place.
  - Why:
    - This protects the n8n editor/admin UI, sessions, login routes, workflow editor, REST/API routes, and static assets from the public internet.
    - It should not be mixed with generic webhook ingress because most webhook senders cannot complete an interactive GitHub login.
  - How:
    - In Cloudflare dashboard, go to Zero Trust -> Access -> Applications.
    - Open the existing application for `n8n.zenaflow.com`.
    - Confirm the application domain includes `n8n.zenaflow.com` and does not unintentionally include `n8n-in.zenaflow.com` unless a path-specific service-token design is being implemented.
    - Confirm the policy still allows the intended GitHub identity, email, or group.
    - Do not replace this policy with a service-token-only policy; service tokens are for machine callers, not the human UI login.

- Keep `n8n-in.zenaflow.com` as a separate webhook ingress hostname instead of unifying it with the UI hostname.
  - Why:
    - One hostname would have to serve two incompatible security models: browser login for humans and non-interactive access for machines.
    - Separate hostnames allow simple Cloudflare and Caddy rules: the UI hostname is private, and the ingress hostname only exposes narrow webhook paths.
    - Incident response and logging are clearer because requests to `n8n-in.zenaflow.com` are expected to be automation traffic.
  - How:
    - Do not add `n8n-in.zenaflow.com` to the same human-login Access application used by `n8n.zenaflow.com` unless using a path-specific bypass/service-token design.
    - Keep n8n's `WEBHOOK_URL` set to `https://n8n-in.zenaflow.com/` in the live and repo Compose configuration.
    - Keep Caddy routing for `n8n-in.zenaflow.com` path-filtered to public n8n ingress paths only.

- Create a Cloudflare WAF Custom Rule that blocks all non-webhook paths on `n8n-in.zenaflow.com`.
  - Why:
    - This rejects scans and accidental browser requests at Cloudflare before they consume VPS resources.
    - It reduces information leakage and makes the public hostname behave like a narrow API ingress, not a general website.
    - Caddy already performs similar path filtering, but Cloudflare should be the first layer of defense.
  - How:
    - In Cloudflare dashboard, open the `zenaflow.com` zone.
    - Go to Security -> WAF -> Custom rules.
    - Create a rule named something like `Block non-n8n-webhook paths on n8n-in`.
    - Use an expression like:
      ```text
      http.host eq "n8n-in.zenaflow.com"
      and not starts_with(http.request.uri.path, "/webhook/")
      and not starts_with(http.request.uri.path, "/webhook-test/")
      and not starts_with(http.request.uri.path, "/form/")
      and not starts_with(http.request.uri.path, "/form-waiting/")
      ```
    - Set the action to `Block`.
    - If `/webhook-test/`, `/form/`, or `/form-waiting/` are not needed publicly, make the rule stricter and allow only `/webhook/`.
    - Prefer `Block` over browser challenges for clearly invalid paths because webhook clients do not interact with challenge pages and invalid paths should simply be rejected.

- Add a Cloudflare Rate Limiting Rule for valid webhook paths.
  - Why:
    - A path allowlist does not stop abusive clients from repeatedly calling allowed webhook URLs.
    - Rate limiting protects n8n, Redis/Postgres, Hermes-backed workflows, and VPS CPU/RAM from accidental loops or hostile traffic.
    - Starting with a conservative limit is safer than leaving the ingress unlimited; the threshold can be tuned after observing real traffic.
  - How:
    - In Cloudflare dashboard, go to Security -> WAF -> Rate limiting rules.
    - Create a rule named something like `Rate limit n8n webhook ingress`.
    - Match at least:
      ```text
      http.host eq "n8n-in.zenaflow.com"
      and starts_with(http.request.uri.path, "/webhook/")
      ```
    - Suggested starting threshold: 60 requests per minute per IP, with action `Block` or `Managed Challenge` for a short mitigation period.
    - If a known integration legitimately bursts above that threshold, either raise the threshold or add a narrower exception for that provider's source IPs/paths.
    - Consider a separate lower threshold for unauthenticated public workflows that are expensive or trigger AI/model calls.

- Decide whether any webhook paths should require Cloudflare Access Service Tokens.
  - Why:
    - Service tokens are stronger than an obscure URL and stop unauthenticated requests at Cloudflare before they reach the VPS.
    - They are only viable for callers that can send custom headers.
    - They should not replace GitHub login on the n8n UI hostname.
  - How:
    - Use service tokens only for machine callers under our control, such as our own backend, scripts, GitHub Actions, cron jobs, or other systems that can send arbitrary HTTP headers.
    - Required request headers are:
      ```text
      CF-Access-Client-Id: <client-id>
      CF-Access-Client-Secret: <client-secret>
      ```
    - In Cloudflare Zero Trust, create a Service Token under Access -> Service Auth -> Service Tokens.
    - Create or update an Access application for `n8n-in.zenaflow.com` only if the protected callers can send these headers.
    - Prefer path-specific protection, for example require service tokens only for `/webhook/private/*`, while leaving `/webhook/public/*` governed by WAF/rate limiting and n8n workflow-level auth.
    - Do not put secrets in browser-side JavaScript or any client where the service-token secret would be exposed.

- Avoid applying a normal human-login Cloudflare Access policy to all of `n8n-in.zenaflow.com` unless every webhook caller is controlled and can authenticate another way.
  - Why:
    - Generic third-party webhook providers usually cannot complete a browser login.
    - A normal Access policy would return a redirect to Cloudflare Access instead of forwarding the webhook request to n8n.
    - That would make external webhook delivery fail even though the DNS and Caddy configuration look correct.
  - How:
    - If third-party webhook providers need to call `n8n-in.zenaflow.com`, keep the hostname outside browser-login Access and rely on WAF, rate limiting, Caddy path filtering, and n8n-level authentication.
    - If only controlled systems need to call the hostname, use Access Service Tokens instead of GitHub/browser login.
    - If both public third-party and private controlled webhooks are needed, split by path: public paths without Access but with WAF/rate limits, private paths requiring service tokens.

- Keep n8n workflow-level authentication on every meaningful webhook.
  - Why:
    - Cloudflare and Caddy protect the ingress surface, but the workflow still needs to verify that a caller is authorized to trigger a business action.
    - Obscure n8n webhook UUIDs are not sufficient as the only protection.
    - Workflows can send messages, call AI services, write data, or trigger infrastructure actions; those should not rely only on path secrecy.
  - How:
    - For each production webhook, choose one of:
      - Bearer token in the `Authorization` header.
      - HMAC signature over the request body using a shared secret.
      - Secret query parameter as a minimum fallback when the caller cannot send headers.
      - Cloudflare Access Service Token for controlled server-to-server callers.
    - In n8n, validate the credential/signature at the beginning of the workflow and stop immediately on failure.
    - Store secrets in n8n credentials/environment where possible, not hard-coded in workflow nodes.

- Verify Cloudflare behavior from outside the VPS after saving the rules.
  - Why:
    - Local origin tests do not prove Cloudflare is enforcing the intended edge policy.
    - Public tests catch accidental Access redirects, missing WAF rules, TLS/certificate issues, and hostname mistakes.
  - How:
    - From a non-VPS machine, run:
      ```bash
      curl -sS -D - -o /dev/null --max-redirs 0 https://n8n.zenaflow.com/
      curl -sS -D - -o /dev/null --max-redirs 0 https://n8n-in.zenaflow.com/
      curl -sS -D - -o /tmp/n8n-in-probe.txt --max-redirs 0 https://n8n-in.zenaflow.com/webhook/__hermes_nonexistent_probe__
      ```
    - Expected results:
      - `n8n.zenaflow.com/` returns a Cloudflare Access redirect for unauthenticated users.
      - `n8n-in.zenaflow.com/` is blocked by Cloudflare WAF or returns origin 404 if the WAF rule has not propagated yet.
      - `n8n-in.zenaflow.com/webhook/__hermes_nonexistent_probe__` reaches n8n and returns a n8n JSON 404 saying the webhook is not registered.
    - Test at least one real active webhook with the expected method and authentication mechanism before declaring the ingress ready.

- Monitor Cloudflare events and VPS logs after enabling the rules.
  - Why:
    - The first few hours reveal whether legitimate webhook senders are being blocked or rate-limited.
    - Logs help distinguish Cloudflare WAF blocks, Caddy path-filter 404s, and n8n-level webhook errors.
  - How:
    - In Cloudflare, review Security -> Events for the new WAF and rate-limiting rule matches.
    - On the VPS, review the Caddy access log for the webhook hostname and n8n logs for expected webhook executions.
    - If legitimate providers are blocked, adjust the WAF path allowlist, rate limit thresholds, or add precise provider-specific exceptions.
    - Do not remove the broad non-webhook-path block unless there is a clear replacement control.

- Document the final Cloudflare choices once configured.
  - Why:
    - Cloudflare dashboard state is not stored in the Git repository by default.
    - Future operators need to know which controls are expected to exist and why.
  - How:
    - Update this plan or `doc/vps_architecture.md` with the final WAF rule names, rate-limit thresholds, any service-token path policy, and the expected public curl behavior.
    - Do not commit service-token secrets or generated client secrets.
    - Record only redacted identifiers and operational behavior.

## Recommended default configuration

Use this as the starting point unless a specific webhook provider cannot comply:

- Keep `n8n.zenaflow.com` behind existing Cloudflare Access GitHub login.
- Keep `n8n-in.zenaflow.com` as the separate public webhook ingress hostname.
- Keep `n8n-in.zenaflow.com` proxied/orange-clouded in Cloudflare DNS.
- Add a WAF Custom Rule blocking all paths except `/webhook/*` initially.
- Temporarily include `/webhook-test/*` only while testing workflows from outside the VPS.
- Include `/form/*` and `/form-waiting/*` only if n8n public forms are actually used.
- Add rate limiting for `/webhook/*`, starting around 60 requests/minute/IP and tuning from observed traffic.
- Use Cloudflare Access Service Tokens only for controlled machine callers and preferably on a private path prefix such as `/webhook/private/*`.
- Require n8n-level authentication or signature validation inside every workflow that performs a meaningful action.
