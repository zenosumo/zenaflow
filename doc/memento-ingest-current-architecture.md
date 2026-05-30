# Memento ingest current architecture

Date: 2026-05-30
Status: implemented watchdog architecture
Related plan: `plans/argo-lazarus-second-brain-v3.md`

## Purpose

Memento is a private Markdown + Git second brain. It is designed for one user, not for organization-scale information retrieval.

The ingest system turns captured raw source notes into structured personal wiki knowledge while preserving provenance and Git history.

In practical terms, `memento-ingest` does this:

1. Reads pending Markdown source files from the Memento vault inbox.
2. Synthesizes durable knowledge into wiki pages.
3. Moves successfully processed sources to the processed raw archive.
4. Updates index, log, followups, and stats metadata.
5. Commits the changes.
6. Pushes them to GitHub.

## Source of truth

GitHub is the canonical source of truth for Memento.

- Repository: `github.com:zenosumo/memento.git`
- Runtime mount in Hermes container: `/memento`
- Canonical state: Markdown files + YAML frontmatter + Git history
- Synchronization model: fetch/rebase before writes, commit/push after writes

Hermes memory is not the source of truth for Memento. The vault repository is.

## Vault role split

The v3 plan defines Memento as a Git-backed Markdown vault with Obsidian as a reader/editor/capture interface.

Current roles:

- Obsidian: capture, reading, light manual edits
- GitHub: sync and audit trail
- Memento vault: actual knowledge store
- default/Argo profile: deterministic orchestration cron owner
- `memento-watchdog`: default-profile script that checks for work and invokes the worker
- `memento-ingest`: bounded AI writer for Stage 1 ingest

Obsidian is not the system. Git + Markdown is the system.

## Current vault layout used by ingest

Relevant paths inside `/memento`:

- `raw/inbox/` — pending source Markdown files
- `raw/processed/` — successfully ingested sources
- `raw/skipped/` — invalid, duplicate, or rejected sources
- `raw/quarantine/` — repeated failures
- `raw/assets/` — source assets
- `raw/.attempts.json` — per-source failure counter
- `wiki/` — synthesized knowledge pages
- `wiki/_meta/stats.json` — cumulative ingest stats
- `index.md` — root overview and recent additions
- `log.md` — ingest activity log
- `followups.md` — proposals, errors, and review items

## Current Hermes profiles

### Default / Argo profile

The default profile now owns the active orchestration schedule.

Active cron job:

```text
job_id: 0994aa381943
name: memento-watchdog
schedule: */30 * * * *
script: memento_watchdog.sh
mode: no-agent
owner profile: default
config path: /opt/data/cron/jobs.json
delivery: local
```

Script files:

```text
/opt/data/scripts/memento_watchdog.sh
/opt/data/scripts/memento_watchdog.py
```

The default profile config sets a longer cron script timeout so the no-agent watchdog can synchronously wait for a bounded ingest worker run:

```text
cron.script_timeout_seconds: 1800
```

### `memento-ingest` profile

Profile home:

```text
/opt/data/profiles/memento-ingest
```

Operating contract:

```text
/opt/data/profiles/memento-ingest/SOUL.md
```

The profile is intentionally bounded. It is not Argo, not a Telegram chatbot, and not a general assistant. Its job is Stage 1 Memento ingestion.

The profile uses:

- model: `gpt-5.5`
- provider: `openai-codex`
- workdir: `/memento`
- memory: disabled for this profile by design

The former self-owned ingest cron is now paused:

```text
job_id: 8a9c512de92b
name: memento-ingest-30m
owner profile: memento-ingest
state: paused
config path: /opt/data/profiles/memento-ingest/cron/jobs.json
```

This means `memento-ingest` no longer owns an active schedule. It is called by the watchdog only when eligible inbox work exists.

## Current execution model

The current flow is:

1. Default-profile Hermes cron fires `memento-watchdog` every 30 minutes.
2. The watchdog script runs with no LLM agent.
3. The script checks that `/memento` is clean.
4. The script fetches/rebases from GitHub.
5. The script inspects `raw/inbox/` for eligible Markdown source files.
6. If no eligible files exist, the script exits with empty stdout. The tick is silent and costs no model call.
7. If eligible files exist, the script invokes `hermes -p memento-ingest chat -q <bounded prompt> -Q`.
8. The `memento-ingest` AI worker reads `SOUL.md` and performs the actual ingest.
9. The worker commits and pushes vault changes.
10. The watchdog returns the worker summary into the default-profile cron output.

The watchdog is orchestration, not ingestion.

## Watchdog script boundary

The watchdog script may:

- fetch/rebase from GitHub
- detect a dirty tree and abort/report
- count eligible files in `raw/inbox/`
- apply deterministic eligibility checks
- call `hermes -p memento-ingest chat -q <prompt>` when work exists
- report worker failures

It should not:

- synthesize wiki pages
- move processed files
- update `index.md`, `log.md`, `stats.json`, or `followups.md`
- perform semantic lint
- duplicate `memento-ingest` business logic
- become a second ingest implementation

## `memento-ingest` responsibilities

The `memento-ingest` worker owns:

- ingest-time dirty tree check
- fetch/rebase before writes
- pending source discovery and deterministic ordering
- small batch processing, currently up to 3 eligible Markdown sources
- provenance updates
- wiki page creation/update
- frontmatter validation on touched wiki pages
- source movement from inbox to processed/skipped/quarantine
- per-source commits
- end-of-run metadata update
- final metadata commit
- push to origin
- operational summary

The worker may still perform its own Git safety checks even though the watchdog also syncs first. Git is cheap; stale assumptions are expensive. A small mammal learned this at the edge of a motorway and contributed nothing further to architecture.

## Current Git behavior

Both layers preserve GitHub as source of truth.

Watchdog preflight:

```text
git status --porcelain
git fetch origin
git rebase origin/main
inspect raw/inbox
```

Worker transaction:

```text
git fetch origin
git rebase origin/main
write changes
git add relevant files
git commit
git push origin HEAD:main
```

On push failure, the worker should fetch/rebase and retry once. On repeated failure, it should surface the problem rather than piling more local commits on top.

This avoids lock files, queues, databases, and message brokers in the vault itself.

## Operational verification

The implemented architecture was verified on 2026-05-30.

Observed behavior:

- legacy `memento-ingest-30m` job paused
- active default-profile `memento-watchdog` job created
- watchdog script dry-run detected eligible inbox files without modifying the vault
- first manual watchdog verification exposed the default 120 second cron script timeout
- default profile config updated: `cron.script_timeout_seconds = 1800`
- subsequent watchdog run completed successfully
- scheduled 03:00 UTC watchdog run completed successfully
- sources moved from `raw/inbox/` to `raw/processed/`
- wiki pages and metadata updated
- commits pushed to GitHub
- repository left clean and synced

Known implementation caveat:

- No-agent scripts that synchronously call AI workers must have a long enough cron script timeout. Otherwise the watchdog can be marked failed even if the child worker continues and succeeds.

## Lint direction

The v3 plan includes lint as a tiered operation. The clean boundary is a separate profile, not expanding `memento-ingest` forever.

Recommended future profile:

```text
memento-lint
```

Recommended responsibilities:

- stuck inbox detection
- repeated failure detection
- malformed frontmatter checks
- missing `level` checks
- broken wikilinks
- orphan notes
- duplicate candidates
- provenance hash checks
- log/index consistency checks
- unfinalized `commit=pending` checks

`memento-ingest` should keep only fast ingest-time lint necessary to validate what it just wrote.

`memento-lint` can run nightly or on demand. It should use tiered behavior:

- auto-fix safe mechanical issues
- propose fixes in `followups.md`
- flag human-only decisions without modifying content

## Dashboard priority

Dashboard visibility is useful, but it must not dictate system boundaries.

The priority order is:

1. Correct functionality
2. Clean role boundaries
3. GitHub as source of truth
4. Cheap empty ticks
5. Observability and dashboard convenience

If dashboard visibility conflicts with clean architecture, architecture wins.

The reason orchestration lives in the main/default profile is not merely dashboard visibility. It is cleaner because orchestration belongs near the operator layer, while ingestion belongs to the bounded worker profile.

## Current recommendation

Keep:

- default profile as the active orchestration owner
- `memento-watchdog` as a deterministic no-agent script-backed cron
- `memento-ingest` as a callable bounded worker
- GitHub as the canonical source of truth
- AI only when there is actual ingest work
- lint in a separate profile when ready

This preserves the v3 plan while reducing token cost and avoiding profile sprawl inside the ingest worker.
