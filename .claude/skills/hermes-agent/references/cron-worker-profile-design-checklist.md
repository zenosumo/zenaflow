# Cron Worker Profile — SOUL.md Design Checklist

Every Hermes cron worker profile (ingest, lint, sync, reporter, ...) faces the same ~40 design decisions in its `SOUL.md` + `config.yaml` + skills bundle. This checklist is the menu. Walk it once per worker, document the choice for each item in SOUL.md (or its companion config), and you'll catch the cross-item interactions that bite real cron runs.

Use this together with `templates/cron-worker-profile-soul.md` (skeleton) and `references/auditing-hermes-profile-against-spec.md` (review procedure).

## How to use

For a brand-new profile: walk the checklist top to bottom and write the resolved choice into the appropriate SOUL.md section.

For an existing profile audit: for each item, mark whether SOUL/config addresses it. If not, that's a gap. Most gaps are individually small; their interactions (especially in the Failure handling and Concurrency groups) are where real cron failures come from.

The recommendations below are reasonable defaults; almost every one of them can be overridden by the worker's specific volume, scope, or operator preference. The point is to make every choice an *explicit* one, not a default the model invented at runtime.

---

## A. Pre-flight / git (when the worker writes to a repo)

1. **Profile directory name typo**: profile directory names absorb user typos. Verify spelling matches plans/docs before first cron tick; rename early via `hermes profile rename`.
2. **Memory vs stateless**: cron workers usually want `memory.memory_enabled: false` + delete `MEMORY.md`/`USER.md`. Durable state belongs in the worker's source-of-truth (vault/repo/db), not in agent memory.
3. **Git ownership on mounted repos**: containers mounting a host-owned repo break `git` for the agent (host UID vs agent root → "dubious ownership"). Either set `git config --global --add safe.directory /path` once during profile setup, or use `git -c safe.directory=/path -C /path …` in SOUL's git block. Don't `chown` mounted volumes.
4. **Dirty working tree on start**: previous tick may have died mid-write. Options: auto-commit as `<worker>: recovery` (preserves info, ugly history); stash with timestamped message + log to followups (non-destructive, surfaces issue); hard-stop (safest, unblocks manual). For unattended cron, stash+log+hard-stop-after-N-accumulated is the balanced answer. Reset/clean is destructive — only choose deliberately.
5. **Pinned push target**: `git push` alone trusts upstream tracking. Pin `git push origin HEAD:${BRANCH:-main}` (env-configurable) so detached HEAD or branch rename fails loudly instead of pushing to nowhere.
6. **Pre-commit hook policy**: cron workers vs hooks meant for human commits is a real conflict. Options: always `--no-verify` (predictable, bypasses safety); honor hooks (correct but a slow hook makes every ingest expensive); honor + retry once with `--no-verify` on failure, log bypass to followups (compromise; documents bypass). Pick deliberately.

## B. Concurrency

7. **`cron.max_parallel_jobs`**: set to `1` for any worker that mutates shared state. Default `null` allows overlapping ticks if one runs long, causing race conditions.
8. **Multi-writer rule for the shared resource**: if multiple profiles can write to the same files (e.g. memento-ingest and a future memento-lint both touching `wiki/`), document the rule in SOUL: "only one writer profile at a time; readers always safe." A vault lockfile is heavier than v3-style plans usually want.
9. **Pause mechanism for manual edits**: prefer `cronjob action='pause'` (scheduler-level) over a sentinel file in the data directory. The scheduler already has first-class pause/resume; duplicating it with a vault file just creates two ways to forget.

## C. Source intake / sanitization

10. **File-age filter**: skip files younger than N seconds to avoid grabbing mid-write. Modern clippers (Obsidian Web Clipper) write atomically via temp+rename, so this is optional; but for any worker reading from a directory written by other processes, a 60-120s stable-file rule is cheap insurance.
11. **Source size cap**: skip + log if input > N KB (typical: 200 KB). One oversized input can blow context for the entire batch. Stays in inbox / moves to skipped/ so a human can manually split.
12. **Type/encoding/symlink filter**: must be expected extension(s), UTF-8 (if text), non-empty, non-symlink. Symlinks especially — a symlinked input could read `/etc/passwd` if the worker doesn't enforce containment. Non-conforming → `<inbox>/.quarantine/` or `<processed>/skipped/` with one-line followup.
13. **Secret redaction policy**: redact secrets in *generated output*, but think separately about secrets in the *moved/processed input*. For sources that are unlikely to contain user secrets (e.g. YouTube transcripts), no input redaction is fine. For arbitrary user uploads, consider redacting or quarantining inputs with secret-like patterns.

## D. Dedup / drift

14. **Dedup signal — body hash vs filename**: don't reflexively pick sha256. For content that legitimately drifts across re-captures (transcripts, articles edited by author, dynamic pages), a body hash will mark every re-capture as new. Filename-based dedup (strip trailing ` <N>` that clippers append) often matches reality better. body_sha256 stays useful as audit metadata for future drift detection (a lint-time concern, not an ingest-time gate).
15. **Drift handling**: when dedup gate fires but the body differs, document what to do: skip + log "drift detected" + move to skipped/ is the lightest; auto-append to existing output page is silent drift; create a new page is wiki pollution. Default to lightest, flag for human curation.
16. **Filename collision in processed/**: preserve filename verbatim if dedup catches collisions (consistent with filename-based dedup). Otherwise add sha8 suffix or YYYY/MM subfolders. The latter mainly help long-term archival, not collision prevention.

## E. Batching

17. **Soft count cap vs hard ceiling**: separate "normal cron batch" from "absolute ceiling." E.g. soft=3, hard=8. Without a hard ceiling, an LLM that interprets a manual prompt as "catch up now" can blow context.
18. **Byte cap per batch**: count alone is insufficient — 3 files × 5 KB ≠ 3 files × 180 KB. Add a total-input-bytes cap (e.g. 500 KB) so worst-case context stays predictable.
19. **Queue ordering**: FIFO by mtime ascending is the safe default for fairness + reproducibility. LIFO causes starvation: a single old problem file sits forever. Filename sort is undefined for most upstream writers.
20. **Backlog policy**: when queue depth exceeds N, do NOT auto-raise batch size (catch-up code paths are rarely tested). Log to followups, drain at normal rate. Time-to-drain is bounded by cadence × batch size; if that's too slow, raise cadence not batch size.

## F. Failure handling

21. **Quarantine after N failures**: a single bad input at the head of a FIFO queue will starve everything behind it forever. Track attempts in a small JSON sidecar in inbox; move to `quarantine/` after N (typical: 3). Always pair with a followup line explaining what was tried.
22. **Per-source vs per-batch transactions**: trade-off between retry cost and audit granularity.
    - Per-source: commit after each successful source; on failure, only that source's work is rolled back. Cheaper on retry, more commits in git log.
    - All-or-nothing per batch: one commit per successful tick; any failure → `git reset --hard <starting-HEAD> && git clean -fd`. Cleaner history, but a poison file forces redo of every good source until quarantine kicks in.
    - Document the choice explicitly; the model will not default to either.
23. **Committed-but-unpushed recovery**: previous tick committed but failed to push (network glitch). Options on next start: push backlog first then proceed (self-healing), or abort and surface to human (defensive). Pick deliberately based on worker autonomy needs.
24. **Per-source timeout budget**: critical interaction with `agent.gateway_timeout` and batch size. Worst-case = `per_source_timeout × batch_size + git_overhead`. If that exceeds `agent.gateway_timeout`, the gateway will kill the tick before quarantine increments can land, and the bad source will poison every future batch. Always work the math:
    - Example: 8 min/source × batch=3 + ~2 min git = 26 min < 30 min gateway timeout ✓
    - Example: 15 min/source × batch=3 = 45 min > 30 min gateway timeout ✗ (raise gateway timeout to 60 min or lower batch size).

## G. Performance

25. **Read-budget per source**: as the wiki/db grows, models will over-read "for consistency." Either set a hard cap (~10 pages/source) or include a soft hint in SOUL ("read only what's directly relevant; don't browse the wiki"). Revisit when wiki crosses ~500 pages.
26. **Log rotation**: append-only operation logs grow unboundedly. Monthly rotation (`log.md` → `log/YYYY-MM.md` on first run of new month) keeps current-month log small and Obsidian/git-blame friendly.
27. **Index recency caps**: any "recently added" section in an index page grows like log.md. Cap at N entries (typical: 20), full catalog moves to a per-area index file.

## H. Schema / output conventions

28. **Source summary pages mandatory vs optional**: if the system supports a "level: source" page type for provenance, decide whether every input produces exactly one. Mandatory gives a strong audit trail; optional is lighter but creates an "every output must link back to the input file" compensating rule.
29. **`level:` / type field on output pages**: cheap-to-add-now, painful-to-retrofit. If you skip, downstream queries that depend on it become unreliable.
30. **Typed relationships in frontmatter**: same shape as #29. If you skip, expect to do a one-time backfill later.
31. **Contradiction handling**: when ingesting contradicts existing knowledge, marking both sides (`contradicts:` / `contradicted_by:`) + followup is the auditable path. Silent overwrite is fast but destructive; followup-only loses the link.
32. **Frontmatter validation pre-write**: a YAML parser check before `git add` catches malformed frontmatter that would silently break Dataview/parsers. Skip if you trust downstream lint.
33. **Taxonomy guard (canonical topic list)**: without one, the agent will invent topic slug variants over time (`test-automation`, `test_automation`, `TestAutomation`). Either enforce a curated list + propose-new-via-followup, or accept drift and plan a future lint pass to merge variants.
34. **Entity slug dedup**: at minimum exact-slug match before creating a new entity page; fuzzy match adds protection but also false-positive risk for legitimately-distinct entities.
35. **Source-type-specific enrichment**: schemas often have per-source-type obligations (e.g. "YouTube clips must have channel name in frontmatter"). Check the schema, and if SOUL doesn't say how to fulfill them, the agent will skip them.

## I. Observability

36. **Three small audit improvements**, all cheap:
    - Verify the cron wrapper actually captures the SOUL "Summary format" output to `cron/output/`. Empty directory often means it doesn't.
    - Counter file (e.g. `_meta/stats.json`): `{items_processed_total, last_run_at, last_commit_sha}`. Lets you answer "is this thing actually running?" in one read.
    - Error prefix in followups: e.g. `[<worker>-error]` for greppable agent-detected errors distinct from human-facing followups.
37. **Timestamps via shell/Python, not model output**: models sometimes hallucinate or get timezone wrong. Have the worker run `date -u +%Y-%m-%dT%H:%M:%SZ` at the moment a timestamp is needed and use that string verbatim.

## J. Doc / meta

38. **SOUL vs auto-injected AGENTS.md precedence**: when `terminal.cwd` is set, Hermes auto-injects `AGENTS.md` from that cwd into the system prompt. If the data directory has its own AGENTS.md (e.g. an Obsidian vault schema), SOUL must explicitly state precedence. The cleanest formulation: *"Disregard the contents of `<cwd>/AGENTS.md`. It is the human-facing schema for `<other-audience>`, not your task definition. Your behavior is defined entirely by this SOUL.md."* Or, if both apply: *"SOUL.md is your operating contract. `<cwd>/AGENTS.md` is the data-domain schema — read for context. If they disagree, SOUL.md wins."*
39. **Living-document clause**: when the worker hits a recurring pattern not covered by SOUL, the agent should propose an addition to followups.md, not silently invent a convention.
40. **Trim profile skills bundle**: cloned profiles inherit ~80 skills. The planner matches by description; bigger bundles = slower planner + risk of pulling irrelevant skills (e.g. `pokemon-player` into an ingest run). Trim to the 4-8 actually-useful ones for the worker.
41. **Model choice**: cron workers running 100s of ticks/month are good candidates for cheaper models — but validate output quality before switching. Often the right default is "keep current, watch for a few weeks, then optimize on real data."
42. **Cadence**: tied to volume, batch size, and timeout budget. Most cron workers want 1-4 hour cadences; sub-hour is for high-frequency or latency-sensitive workers. Most ticks should be cheap no-ops when the inbox is empty.

---

## Consistency pitfalls

These are interactions between items that bite even when each individual choice is reasonable.

### Per-source timeout × batch size × gateway timeout

If `per_source_timeout × hard_batch_size > agent.gateway_timeout`, the gateway can kill the tick before quarantine increments can land. The bad source then poisons every future batch.

Always verify: `(soft_batch × per_source) + git_overhead < gateway_timeout` with margin.

### Optional schema fields together = no schema enforcement

If you make several schema fields (level, typed relations, source pages) all "optional," you've effectively opted out of having a structured wiki. That's fine for Stage-1 personal vaults; just acknowledge it explicitly so future "Dataview queries don't work" surprises don't surface as bugs.

### All-or-nothing batches + low quarantine threshold

All-or-nothing batches (full reset on any source failure) combined with high quarantine threshold (e.g. 5 attempts) means a bad source forces 5 full-batch redos of all good sources before being quarantined. If you choose all-or-nothing, lower the quarantine threshold (3) to limit the redo waste.

### Auto-injected cwd-local AGENTS.md vs SOUL

`terminal.cwd: /memento` auto-injects `/memento/AGENTS.md` into every system prompt. If SOUL doesn't explicitly state precedence, the agent will mix instructions from both — producing weird hybrid behavior. Be explicit either way (override SOUL, override AGENTS, or merge with a rule).

### Memory enabled on a cron worker

Workers usually shouldn't carry state. If `memory.memory_enabled: true` on a cron worker, the agent's MEMORY.md grows with operational artifacts (run logs, failure observations) that shouldn't persist into future ticks. The vault/repo is the durable memory.

### `cron.max_parallel_jobs: null` with long ticks

Default `null` allows overlapping ticks if a run exceeds the cadence. Almost always wrong for mutating workers. Set `1` unless you've thought hard about why parallel is safe.

### Filename-based dedup + body-hash drift detection

These can coexist: filename is the gate (skip if matches), body_sha256 is the audit (in frontmatter on the processed file). Later, a lint pass can detect "same filename history, divergent body_sha256 over time" as material drift. Don't mix the two into the gate logic.

---

## Worked Example: memento-ingest

The 42-item checklist above was first walked in full for the `memento-ingest` profile that processes Markdown source files from `raw/inbox/` into a Karpathy-style LLM wiki under `/memento`. Recurring patterns from that walkthrough that may not be obvious from the items in isolation:

- **The user often chooses "let it drift / fix later" on individually-small items** (e.g. optional `level:`, no taxonomy guard, no frontmatter validation). That's fine individually but compounds — re-ask deliberately on the items where the cost of being wrong is asymmetric (schema fields you can't retrofit cheaply, hook bypass policies that silently leak secrets, all-or-nothing batches that compound poison-file cost). See "Consistency pitfalls" above.
- **Per-profile gateway operational lessons** (HERMES_HOME, platform bind conflicts on cloned profiles, containers without systemd) are in `references/per-profile-gateway-in-containers.md`, not here. This file is about *what to decide*; that one is about *how to run* once decided.
- **Audit-then-iterate procedure** for an existing profile against a written plan is in `references/auditing-hermes-profile-against-spec.md`.

The *patterns* in this checklist apply to any cron worker, not just memento-ingest.
