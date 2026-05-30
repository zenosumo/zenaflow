# Memento ingest current architecture

Date: 2026-05-30
Status: as-is documentation
Related plan: `plans/argo-lazarus-second-brain-v3.md`

## Purpose

Memento is a private Markdown + Git second brain. It is designed for one user, not for organization-scale information retrieval.

The current ingest system exists to turn captured raw source notes into a structured personal knowledge wiki while preserving provenance and Git history.

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
- `memento-ingest`: bounded AI writer for Stage 1 ingest
- Argo/default profile: operator-facing assistant and orchestration candidate

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

## Current Hermes profile

Profile name: `memento-ingest`

Profile home:

```text
/opt/data/profiles/memento-ingest
```

Current operating contract:

```text
/opt/data/profiles/memento-ingest/SOUL.md
```

The profile is intentionally bounded. It is not Argo, not a Telegram chatbot, and not a general assistant. Its job is Stage 1 Memento ingestion.

The profile uses:

- model: `gpt-5.5`
- provider: `openai-codex`
- workdir: `/memento`
- memory: disabled for this profile by design

## Current cron job

Current job ID:

```text
8a9c512de92b
```

Current job name:

```text
memento-ingest-30m
```

Current schedule:

```text
*/30 * * * *
```

Current profile owner:

```text
memento-ingest
```

Current job config path:

```text
/opt/data/profiles/memento-ingest/cron/jobs.json
```

Current delivery:

```text
local
```

Current workdir:

```text
/memento
```

## Current execution model

As of this document, the cron job does not call a deterministic ingest script.

The current flow is:

1. Hermes cron scheduler fires the job under the `memento-ingest` profile.
2. Hermes starts an AI agent run using the job prompt.
3. The prompt instructs the worker to read and obey `SOUL.md`.
4. The AI worker uses Hermes tools to inspect and modify the vault.
5. The AI worker runs Git commands through the terminal tool.
6. The worker commits and pushes the resulting vault changes.
7. Hermes stores the final summary under the profile cron output directory.

Current job-level fields:

```text
script: null
no_agent: false
```

This means the cron job invokes the AI directly. There is no preflight script at the cron layer.

## Current ingest responsibilities

The `memento-ingest` worker currently owns:

- pre-flight dirty tree check
- fetch/rebase before work
- pending source discovery
- small batch processing
- provenance updates
- wiki page creation/update
- frontmatter validation on touched wiki pages
- source movement from inbox to processed/skipped/quarantine
- per-source commits
- end-of-tick metadata update
- final metadata commit
- push to origin
- operational summary

The current batch target is up to 3 pending eligible Markdown sources per normal tick.

## Current Git behavior

The operating contract follows the v3 coordination model:

```text
git fetch origin
git rebase origin/main
write changes
git add relevant files
git commit
git push origin HEAD:main
```

On push failure, the worker should fetch/rebase and retry once. On repeated failure, it should surface the problem rather than piling more local commits on top.

This keeps GitHub as source of truth and avoids lock files, queues, databases, and message brokers.

## Current observed behavior

A recent manual run verified the current system can process files end to end:

- 3 pending sources processed
- sources moved from `raw/inbox/` to `raw/processed/`
- wiki pages updated
- metadata updated
- commits created
- push completed
- repository left clean and synced

This confirms the current AI-direct cron model works operationally.

## Known architectural concern

The current cron job is both scheduler and doer inside the same worker profile.

That works, but it has costs:

- Empty ticks still invoke the AI unless prevented elsewhere.
- The ingest profile owns its own schedule instead of being called only when needed.
- Dashboard visibility is profile-scoped, so this job may not appear in the default-profile dashboard.
- The AI has to discover there is no work after the model call has already happened.

This is functional, but not the cheapest or cleanest long-term shape.

## Preferred next architecture under discussion

The preferred direction is to separate orchestration from ingestion without changing the worker boundary.

Proposed shape:

- default/main profile owns a lightweight cron orchestration job
- that cron job runs a deterministic watchdog script
- the watchdog script checks GitHub-backed vault state and inbox eligibility
- if no eligible files exist, it exits silently without calling an LLM
- if eligible files exist, it calls the `memento-ingest` profile once
- `memento-ingest` remains the bounded AI worker and performs the actual ingest

Potential names:

- cron job: `memento-watchdog`
- script: `memento_watchdog.py`
- worker profile: `memento-ingest`

## Watchdog script boundary

A future watchdog script should be deliberately boring.

It may:

- fetch/rebase or otherwise sync from GitHub
- detect a dirty tree and abort/report
- count eligible files in `raw/inbox/`
- apply deterministic eligibility checks
- call `hermes -p memento-ingest chat -q <prompt>` when work exists
- report worker failures
- verify after a worker run that the repo is clean and pushed

It should not:

- synthesize wiki pages
- move processed files
- update `index.md`, `log.md`, `stats.json`, or `followups.md`
- perform semantic lint
- duplicate `memento-ingest` business logic
- become a second ingest implementation

The watchdog is orchestration, not ingestion.

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

The reason to move orchestration to the main/default profile is not merely dashboard visibility. It is cleaner because orchestration belongs near the operator layer, while ingestion belongs to the bounded worker profile.

## Current recommendation

Do not move `memento-ingest` itself into the default profile.

Do eventually move scheduling/orchestration out of `memento-ingest` and into a script-backed main-profile cron job.

Keep:

- `memento-ingest` as a callable bounded worker
- GitHub as the canonical source of truth
- deterministic preflight in a watchdog script
- AI only when there is actual ingest work
- lint in a separate profile when ready

This preserves the v3 plan while reducing token cost and avoiding profile sprawl inside the ingest worker.
