# Hermes + Second Brain: Implementation Plan

## Overview

Deploy Hermes Agent on the VPS as a persistent AI agent integrated with a new
Obsidian-based second brain vault. The vault (GitHub private repo) is the
knowledge layer; Hermes is the intelligence layer that processes, maintains,
and reasons over it. Local machine is capture-only.

**Philosophy:** verify each component works in isolation before connecting
anything. Each phase ends with a checkpoint. Do not proceed to the next phase
until the checkpoint passes.

**Key URLs:**
- Hermes dashboard: `argo.zenaflow.com`
- Hermes gateway API: internal port 8642
- Vault location (VPS): `/opt/vault`
- Hermes data (VPS): `/opt/core/hermes_data`

---

## Architecture Summary

```
macOS (local)
  Obsidian desktop        ← read vault, browse wiki
  Obsidian Web Clipper    ← capture → vault/raw/
  Obsidian Git plugin     ← auto-push to GitHub on every save

GitHub (private repo: zenaflow-vault)
  ← sync bridge between local and VPS

VPS /opt/vault            ← vault clone, Hermes reads/writes here
VPS /opt/core/hermes_data ← Hermes agent state (memories, skills, sessions)

Hermes (Docker, core_net)
  ← git pull cron: syncs vault from GitHub
  ← processes raw/ → builds wiki/, journal/, people/
  ← git push: sends processed content back to GitHub
  ← Telegram gateway: chat/journal from anywhere
  ← Dashboard: argo.zenaflow.com

Write permissions:
  Local   → raw/ only
  Hermes  → wiki/, journal/, people/, index.md, log.md
  You     → agents.md (Hermes instruction set, edit in Obsidian)
```

---

## Phase 1 — Hermes on VPS (terminal only)

Goal: Hermes running in Docker, responding in terminal. Nothing else connected.

### 1.1 OpenAI API Key

> **Note:** A ChatGPT Plus/Pro subscription does NOT include API access.
> Hermes requires an API key from platform.openai.com (separate billing,
> pay-per-use). Check if you already have an account at platform.openai.com.
> If not, create one and add a small credit balance.

- [ ] Confirm API key available at platform.openai.com
- [ ] Note the key securely

### 1.2 Create hermes_data directory

```bash
mkdir -p /opt/core/hermes_data
chmod 755 /opt/core/hermes_data
```

> **Permissions note:** The Hermes container drops to a non-root user (UID 10000)
> by default. Since the VPS runs as root, we set `HERMES_ALLOW_ROOT_GATEWAY=1`
> and `HERMES_UID=0` so the container runs as root and can read/write the vault
> without permission errors when we connect it later.

### 1.3 Create hermes_data/.env

> **Important:** Secrets live inside the data volume at `/opt/core/hermes_data/.env`.
> Hermes reads this file natively on startup. Do NOT use Docker's `env_file:`
> directive — that bypasses Hermes' own secrets manager.

```bash
cat > /opt/core/hermes_data/.env << 'EOF'
# OpenAI
OPENAI_API_KEY=sk-...

# API server key for n8n and external tool access (min 8 chars)
# Generate with: openssl rand -hex 32
API_SERVER_KEY=<generated_key>

# Telegram — add after Phase 3
# TELEGRAM_BOT_TOKEN=...
# TELEGRAM_ALLOWED_USERS=<your_numeric_user_id>
# TELEGRAM_HOME_CHANNEL=-1001234567890
EOF

chmod 600 /opt/core/hermes_data/.env
```

Generate the API server key:
```bash
openssl rand -hex 32
```

### 1.4 Add hermes service to docker-compose.yml

Add to `/opt/core/docker-compose.yml` inside the `services:` block.
Note: no vault mount yet — that is added in Phase 6.

```yaml
  hermes:
    image: nousresearch/hermes-agent:latest
    container_name: hermes
    restart: unless-stopped
    command: gateway run
    ports:
      - "127.0.0.1:8642:8642"   # gateway API (internal only)
      - "127.0.0.1:9119:9119"   # dashboard (proxied by Caddy)
    volumes:
      - ./hermes_data:/opt/data  # Hermes agent state
    environment:
      - HERMES_DASHBOARD=1
      - HERMES_DASHBOARD_HOST=0.0.0.0
      - HERMES_DASHBOARD_PORT=9119
      # - HERMES_DASHBOARD_TUI=1    # Optional: in-browser chat tab
      - HERMES_ALLOW_ROOT_GATEWAY=1
      - HERMES_UID=0
      - API_SERVER_ENABLED=true
      - API_SERVER_HOST=0.0.0.0
      # API_SERVER_KEY loaded from /opt/data/.env inside the volume
    shm_size: "1g"               # Required for browser/Playwright tools
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: "2.0"
    networks:
      - core_net
```

### 1.5 Run Hermes setup wizard (first boot, interactive)

```bash
cd /opt/core
docker compose pull hermes
docker run -it --rm \
  -v /opt/core/hermes_data:/opt/data \
  nousresearch/hermes-agent setup
```

During setup:
- Select OpenAI as provider
- Set model to `gpt-4o` (or latest available)
- Skip Telegram for now — configured in Phase 3

### 1.6 Start Hermes and test in terminal

```bash
cd /opt/core
docker compose up -d hermes
docker compose logs -f hermes
```

Open a terminal session inside Hermes:
```bash
docker exec -it hermes hermes
```

Send a test message and confirm a response.

### ✅ Checkpoint 1
- [ ] Hermes container is running (`docker compose ps`)
- [ ] Hermes responds to messages in terminal

---

## Phase 2 — Caddy + DNS (expose dashboard)

Goal: `argo.zenaflow.com` resolves and shows the Hermes dashboard.

### 2.1 Add argo.zenaflow.com to Caddyfile

Add to `/opt/zenaflow/caddy/Caddyfile`:

```caddyfile
argo.zenaflow.com {
  log {
    output file /var/log/caddy/argo_access.log {
      roll_size 10MiB
      roll_keep 7
      roll_keep_for 336h
    }
    format json {
      time_format iso8601
    }
  }
  reverse_proxy 127.0.0.1:9119
}
```

### 2.2 Validate and reload Caddy

```bash
caddy validate --config /opt/zenaflow/caddy/Caddyfile
caddy reload --config /opt/zenaflow/caddy/Caddyfile
```

### 2.3 Add Cloudflare DNS record

Via Cloudflare dashboard or MCP tool:
- Type: `A`
- Name: `argo`
- Content: VPS IP address (same as other records)
- Proxy: Enabled (orange cloud)

### ✅ Checkpoint 2
- [ ] `curl http://127.0.0.1:9119` returns HTML
- [ ] `argo.zenaflow.com` loads the dashboard in browser

> **Dashboard note:** The dashboard runs as a background process inside the
> container (not supervised by Docker). If it crashes it stays down until the
> container restarts. Monitor with:
> `docker compose logs -f hermes | grep dashboard`

---

## Phase 3 — Telegram (complete Hermes communication)

Goal: chat with Hermes from Telegram on your phone.

### 3.1 Create Telegram bot

- [ ] Message [@BotFather](https://t.me/BotFather) → `/newbot`
- [ ] Choose display name (e.g. "Argo") and username ending in `bot`
- [ ] Save the bot token: `123456789:ABCdef...`
- [ ] Message [@userinfobot](https://t.me/userinfobot) → save your numeric user ID

### 3.2 Add Telegram credentials to hermes_data/.env

```bash
# Edit /opt/core/hermes_data/.env and uncomment/fill:
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=<your_numeric_user_id>
```

### 3.3 Configure Telegram in Hermes

```bash
docker exec -it hermes hermes gateway setup
# Select Telegram, paste token and user ID
```

### 3.4 Restart Hermes to pick up new credentials

```bash
cd /opt/core
docker compose restart hermes
```

### ✅ Checkpoint 3 — Hermes fully operational
- [ ] Send a message to your Argo bot on Telegram
- [ ] Hermes responds
- [ ] Dashboard accessible at `argo.zenaflow.com`
- [ ] Terminal session works via `docker exec -it hermes hermes`

---

## Phase 4 — Obsidian local (macOS)

Goal: capture working locally. Web Clipper saves to `raw/`, visible in Obsidian.
No GitHub yet.

### 4.1 Create vault folder structure locally

```bash
mkdir -p ~/Documents/vault/raw/assets
mkdir -p ~/Documents/vault/raw/processed
mkdir -p ~/Documents/vault/wiki/relationship
mkdir -p ~/Documents/vault/wiki/job-hunting
mkdir -p ~/Documents/vault/wiki/diet
mkdir -p ~/Documents/vault/journal
mkdir -p ~/Documents/vault/people
```

### 4.2 Create initial vault files

**`~/Documents/vault/index.md`**:
```markdown
# Vault Index

## Wiki
- [Relationship](wiki/relationship/) — relationship strategies, social dynamics
- [Job Hunting](wiki/job-hunting/) — expert knowledge, interview strategies, career advice
- [Diet](wiki/diet/) — nutrition, health, diet protocols

## Journal
- [Journal](journal/) — personal journal entries

## People
- [People](people/) — contact records and relationship notes

## Sources
<!-- Hermes appends source entries here on each ingest -->
```

**`~/Documents/vault/log.md`**:
```markdown
# Activity Log

<!-- Format: ## [YYYY-MM-DD] operation | title -->
<!-- Hermes appends entries here. Do not edit manually. -->
```

**`~/Documents/vault/agents.md`** — see Phase 6.3 for full content.
Create an empty placeholder for now:
```markdown
# Vault Agents
<!-- Hermes instruction set — filled in Phase 6 -->
```

**`~/Documents/vault/.gitignore`**:
```
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.trash/
```

### 4.3 Install Obsidian

- Download from obsidian.md → install on macOS
- Open Obsidian → "Open folder as vault" → select `~/Documents/vault`

### 4.4 Configure Obsidian settings

Settings → Files and links:
- Attachment folder path: `raw/assets`
- Enable "Automatically update internal links"

Settings → Hotkeys → search "Download attachments" → bind to `Cmd+Shift+D`

### 4.5 Install Obsidian Web Clipper (Chrome)

- Install from Chrome Web Store: "Obsidian Web Clipper" (official, by Obsidian)
- Extension settings:
  - Vault: `vault` (must match exactly the vault name shown in Obsidian bottom-left)
  - Default template:
    ```
    ---
    source_title: {{title}}
    source_url: {{url}}
    date_clipped: {{date}}
    tags: [web-clip]
    ---

    {{content}}
    ```
  - Note location: `raw`

### 4.6 Recommended Obsidian plugins (optional)

- **Dataview** — query vault by frontmatter
- **Templater** — smarter templates for journal and people records
- **Graph Analysis** — enhanced graph view

### ✅ Checkpoint 4
- [ ] Clip any web page → file appears in `raw/` in Obsidian
- [ ] Clip a YouTube video → transcript appears in the clipped file

---

## Phase 5 — Vault on GitHub

Goal: vault synced to a private GitHub repo, auto push/pull working.

### 5.1 Create GitHub private repo

- [ ] Create new **private** repository: `zenaflow-vault`
- [ ] Do not initialise with README
- [ ] Note remote URL: `git@github.com:<username>/zenaflow-vault.git`

### 5.2 Push local vault to GitHub

```bash
cd ~/Documents/vault
git init
git add -A
git commit -m "init: vault structure"
git remote add origin git@github.com:<username>/zenaflow-vault.git
git push -u origin main
```

### 5.3 Install Obsidian Git plugin

Settings → Community plugins → Browse → search "Obsidian Git" → install and enable

Configure:
- Auto pull interval: 5 minutes
- Auto push interval: 5 minutes
- Commit message: `sync: {{date}}`
- Pull on startup: enabled

### ✅ Checkpoint 5 — Vault fully operational
- [ ] Clip something → file appears in `raw/` in Obsidian
- [ ] Within 5 minutes → commit and push appears on GitHub
- [ ] Manually trigger pull → local vault receives any remote changes

---

## Phase 6 — Connect Vault to Hermes (VPS)

Goal: Hermes can read and write the vault. First integration point.

### 6.1 Add VPS SSH key to GitHub repo

```bash
# Check VPS SSH public key
cat ~/.ssh/id_ed25519.pub
```

Add this key as a **Deploy Key with write access** in GitHub:
`zenaflow-vault` repo → Settings → Deploy keys → Add deploy key

### 6.2 Clone vault on VPS

```bash
cd /opt
git clone git@github.com:<username>/zenaflow-vault.git vault
```

### 6.3 Write agents.md on VPS

Replace the placeholder with the full instruction set:

```bash
cat > /opt/vault/agents.md << 'EOF'
# Vault Agents

This vault is managed by Hermes Agent running on the VPS at core.zenaflow.com.
The vault is a personal second brain structured around four domains:
relationship, job hunting, diet, and people.

## Vault Structure

- `raw/` — immutable source files dropped by the user via Obsidian Web Clipper.
  Never modify files here. After processing, move them to `raw/processed/`.
- `raw/assets/` — locally downloaded images referenced in raw files.
- `wiki/` — LLM-generated knowledge pages organised by domain.
- `journal/` — personal journal entries with AI responses grounded in the wiki.
- `people/` — CRM contact records for individuals.
- `index.md` — master catalog of all wiki pages and sources.
- `log.md` — append-only chronological activity log.

## Operations

### INGEST
Triggered when unprocessed files are found in `raw/`.

1. Read the source file from `raw/`.
2. If it is a YouTube video clip, extract the channel name from the source URL
   and add it to the file's YAML frontmatter as `channel:`.
3. Summarise the source and extract key concepts, entities, people, tools,
   and themes.
4. Determine which wiki domain(s) this source belongs to:
   - relationship strategies, dating, social skills → `wiki/relationship/`
   - career advice, interviews, job market, productivity → `wiki/job-hunting/`
   - nutrition, diet, health, food → `wiki/diet/`
5. Create or update relevant wiki pages in the appropriate domain folder.
   Each wiki page must have YAML frontmatter: title, tags, sources (list),
   last_updated date.
6. Cross-link all generated/updated wiki pages back to the original source
   file using `[[wikilink]]` syntax.
7. Update `index.md` with new or updated pages.
8. Append an entry to `log.md`:
   `## [YYYY-MM-DD] ingest | <source title>`
9. Move the source file from `raw/` to `raw/processed/`.

### QUERY
When the user asks a question (via Telegram or dashboard chat):

1. Read `index.md` to find relevant wiki pages.
2. Read those pages and synthesise an answer with citations to source files.
3. If the answer is substantive and reusable, save it as a new wiki page.
4. Append a query entry to `log.md`.

### JOURNAL
When the user starts a message with `journal:` or sends a journal entry:

1. Read `index.md` and identify wiki pages relevant to the journal topic.
2. Read recent journal entries in `journal/` for patterns.
3. Write a response grounded in the wiki content and past journal history.
4. Save the full journal entry + response as a new markdown file in `journal/`.
   Filename format: `YYYY-MM-DD-short-title.md`
5. Update the journal index at `journal/index.md`.
6. Append to `log.md`: `## [YYYY-MM-DD] journal | <title>`

### PERSON (CRM)
When the user provides information about a person:

1. Check `people/` for an existing contact record with that name.
2. Create or update the contact file: `people/<Firstname-Lastname>.md`
3. Record: name, contact details, how/where met, relationship context,
   notes from conversations, connections to wiki topics.
4. Update `people/index.md` (alphabetical list with one-line summary).
5. Append to `log.md`: `## [YYYY-MM-DD] crm | <person name>`

### LINT
When asked to health-check the vault:

1. Find orphan wiki pages (no inbound wikilinks).
2. Find wiki pages not listed in `index.md`.
3. Find contradictions between pages in the same domain.
4. Suggest new sources based on gaps in current wiki coverage.
5. Report findings as a markdown summary.

## Git Workflow

Before starting any operation:
1. `git pull origin main`

After completing any write operation:
1. `git add -A`
2. `git commit -m "<operation>: <short description>"`
3. `git push origin main`

## Cron Schedule

- Every 15 minutes: `git pull` → check `raw/` for unprocessed files →
  if any found, run INGEST → `git push`.
- Daily at 08:00: run LINT → append report to `log.md` → `git push`.

## n8n Integration

The VPS runs n8n at workflow.zenaflow.com. Hermes can:
- List available workflows via the n8n API
- Trigger workflow executions by workflow ID
- Check execution status
Use the n8n skill when the user asks to run or check an automation.
EOF
```

Commit and push agents.md:
```bash
cd /opt/vault
git add agents.md
git commit -m "agents: add Hermes instruction set"
git push origin main
```

### 6.4 Add vault volume to docker-compose.yml

Update the hermes service volumes in `/opt/core/docker-compose.yml`:

```yaml
    volumes:
      - ./hermes_data:/opt/data  # Hermes agent state
      - /opt/vault:/vault        # Second brain vault
```

Also add to environment:
```yaml
      - OBSIDIAN_VAULT_PATH=/vault
```

### 6.5 Restart Hermes with vault mounted

```bash
cd /opt/core
docker compose up -d hermes
```

### ✅ Checkpoint 6
- [ ] Via Telegram: "list the files in /vault" → Hermes lists vault contents
- [ ] Via Telegram: "read /vault/index.md" → Hermes returns the index

---

## Phase 7 — Hermes Cron + Processing

Goal: full pipeline working — clip on macOS → wiki page appears in Obsidian.

### 7.1 Configure vault sync cron via Telegram

Send to Hermes on Telegram:
> "Set up a recurring task every 15 minutes: first run `git pull origin main`
> in /vault, then check /vault/raw/ for any markdown files not in
> /vault/raw/processed/. If any found, process each one following the INGEST
> operation in /vault/agents.md. After processing, run `git add -A`,
> `git commit`, and `git push origin main` in /vault."

### 7.2 Configure daily lint cron via Telegram

> "Set up a daily task at 08:00: run the LINT operation in /vault/agents.md
> and append the report to /vault/log.md, then push to git."

### 7.3 Test the full pipeline

1. On macOS: clip a YouTube video with Web Clipper → file lands in `raw/`
2. Obsidian Git plugin auto-pushes → file appears on GitHub
3. Wait up to 15 min → Hermes cron fires, pulls, processes
4. Wiki page appears in `/vault/wiki/` → pushed to GitHub
5. Obsidian Git plugin auto-pulls → wiki page appears in local Obsidian

### ✅ Checkpoint 7 — Full integration working
- [ ] Clipped file appears in GitHub `raw/` within 5 min
- [ ] Wiki page appears in GitHub `wiki/` within 15 min of clip
- [ ] Wiki page appears in local Obsidian automatically
- [ ] Journal entry via Telegram → response grounded in wiki, saved to `journal/`
- [ ] Person added via Telegram → CRM record in `people/`

---

## Phase 8 — n8n Skill

Goal: Hermes can list and trigger n8n workflows. Done last, once everything stable.

The n8n API is available at `http://n8n:5678/api/v1` (on `core_net`).

Via Telegram:
> "Create a skill that lets you interact with n8n. You can list all workflows,
> trigger a workflow by ID, and check execution status. The n8n API is at
> http://n8n:5678/api/v1 on the internal Docker network. Store the API key
> in your .env file."

Hermes writes this as a reusable skill in `hermes_data/skills/`.

### ✅ Checkpoint 8
- [ ] Via Telegram: "list my n8n workflows" → Hermes returns workflow list

---

## Upgrading Hermes

```bash
cd /opt/core
docker compose pull hermes
docker compose up -d hermes
# All data in hermes_data/ is preserved
```

---

## Notes & Decisions

- **OpenAI API key vs subscription**: ChatGPT Plus/Pro does NOT include API
  access. A separate account at platform.openai.com is required.
- **Vault write rules**: local writes only to `raw/`. Hermes writes everything
  else. This prevents git merge conflicts.
- **agents.md**: living documentation. Edit it in Obsidian to change Hermes
  behaviour. No code deployments needed.
- **Memory**: Hermes built-in FTS5 to start. Qdrant upgrade available when
  vault exceeds ~100K docs.
- **n8n integration**: implemented as a Hermes skill, not native integration.
  Hermes writes and refines the skill autonomously.
- **Two repos**: `zenaflow` (infra) and `zenaflow-vault` (knowledge) are
  completely separate. Never mix them.
