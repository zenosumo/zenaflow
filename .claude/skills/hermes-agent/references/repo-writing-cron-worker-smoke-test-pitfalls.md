# Repo-writing cron worker smoke-test metadata pitfalls

Session pattern: a cron-only Hermes profile was tested manually against a Git-backed Markdown vault. The smoke test succeeded functionally, but verification exposed two contract issues that should be caught before recurring cron is enabled.

## Commit SHA in files written by the same commit

A worker cannot reliably write the final commit SHA into `log.md`, `stats.json`, or similar files inside the same commit, because the SHA is only known after the commit object is created. If the contract asks for `commit=<sha>` in a file being committed, workers may invent or precompute an incorrect value.

Preferred contract shapes:

- Use `commit=pending` or omit commit SHA in committed logs.
- Report actual commit SHAs in the final operational summary after the commit succeeds.
- If committed files must contain the SHA, make that an explicit two-commit workflow: commit content first, then make a correction/metadata commit. Do not let the worker silently fake the value.

Verification step:

- Compare `git log --oneline` / `git rev-parse HEAD` with any committed SHA fields in logs/stats.
- If they mismatch, correct the repo before cron rollout and patch the worker contract.

## FIFO tie-breakers

When a queued worker processes the "oldest" file by mtime, many files may have identical mtimes after bulk copy/import. Without a tie-breaker, directory iteration order can make the selected file look arbitrary.

Preferred contract wording:

`Order: FIFO by mtime ascending (oldest first). If multiple files have the same mtime, break ties by filename ascending for deterministic behavior.`

Verification step:

- Before the smoke test, print the first few candidate files sorted by the exact contract rule.
- After the smoke test, confirm the processed file matches that deterministic order.

## log.md structural issues (confirmed pattern)

Even after patching SOUL.md, workers tend to produce log.md entries with these defects after a manual or cron run:

1. **Machine log lines appended directly after prose sections** — the worker appends timestamped ingest lines immediately after old `##` prose sections with no blank line, making log.md look broken. Fix in SOUL: explicitly instruct the worker to ensure a `## [YYYY-MM-DD] ingest activity` heading exists for the current UTC date before appending any machine lines, and never append machine lines directly onto prose.

2. **commit=pending not resolved** — the worker writes `commit=pending` during per-source commits (correct, SHA is unknown) but then fails to replace those lines with real SHAs in the end-of-tick meta commit. Fix in SOUL: explicitly require an "in-memory tick map" (source filename → real short SHA) and a mandatory rewrite pass before the meta commit, with a hard rule that no `commit=pending` lines from the current tick may remain on success.

3. **tick-summary before per-source lines** — summary line appears at the top of the section before the individual source lines, inverting expected chronological order. Fix in SOUL: specify that per-source lines are appended first, summary line appended last.

4. **Failed-attempt entries from internal retries left in log** — when a worker retries a batch internally, log lines from the failed attempt remain alongside the successful entries. Fix in SOUL: failed-attempt log lines should only be written when the failure is final (source moves to quarantine or is abandoned for this tick), not on internal retries.

**Operator correction procedure** (when these defects appear after a run):

- Identify real commit SHAs via `git log --oneline`.
- Rewrite affected `log.md` section: correct order (per-source lines ascending, summary last), real SHAs, remove spurious failed-attempt entries.
- Commit and push the correction as `chore: fix log.md ...`.
- Do not amend source commits.

## Dashboard model-usage discrepancy

The Hermes dashboard shows model usage for the **default profile**, not profile-local CLI sessions. If you run `hermes -p <profile> chat -q ...` manually, that session is recorded under the profile's own `sessions/` directory and state DB, but may not appear in the dashboard's model-usage widget. To verify which model and provider were actually used:

- Check `$HERMES_HOME/profiles/<profile>/sessions/session_<id>.json` — top-level `"model"` and `"base_url"` fields.
- Check `$HERMES_HOME/profiles/<profile>/logs/agent.log` — look for lines like `Gemini native client created ... provider=gemini model=gemini-3.5-flash`.
- Check the profile state DB `state.db` sessions table — `model`, `billing_provider`, `billing_base_url` columns.

These are authoritative even if the dashboard disagrees.

## Cron job creation: repeat=forever requires "every Xm" syntax

`cronjob(action='create', schedule='30m')` creates a **one-shot** job (`repeat: once`, runs once then stops).

To create a **recurring** job that repeats forever, use:

```python
cronjob(action='create', schedule='every 30m')  # repeat: forever
```

The `"every "` prefix is what triggers `repeat: forever`. Without it, the job fires once. Verify with `cronjob(action='list')` and confirm `"repeat": "forever"` in the response before declaring the job live.

## Cron job creation: `cronjob` tool creates jobs in the CURRENT session profile, not the target worker profile

**Critical pitfall.** When you call `cronjob(action='create', ...)` from within an interactive Argo/default session, the job is registered under the **default profile's** cron store — NOT under the worker profile you intended. The worker profile's gateway will never see it and it will never fire.

Symptom: `hermes -p memento-ingest cron list --all` returns "No scheduled jobs" even though `hermes cron list` shows the job.

**Correct procedure** — always create worker profile cron jobs via the CLI with `-p`:

```bash
hermes -p <worker-profile> cron create 'every 30m' '<prompt>' \
  --name '<job-name>' \
  --deliver local \
  --workdir /path/to/workdir
```

Do NOT use the `cronjob(...)` tool from within the main chat session for worker-profile jobs. The tool runs in the session's profile context, which is the default/current profile.

**Also check `jobs.json` ownership** — if the profile was set up by root and the gateway runs as `hermes` user, the file may be owned by root and unwritable:

```bash
ls -la /opt/data/profiles/<worker>/cron/jobs.json
# Fix if needed:
chown hermes:hermes /opt/data/profiles/<worker>/cron/jobs.json
```

**Verification after creation:**

```bash
hermes -p <worker-profile> cron list --all   # must show the job here
hermes cron list --all                        # must NOT show it here (or it's in wrong profile)
```

## User-facing rollout rule

If a smoke test succeeds but reveals contract ambiguity, patch the worker profile contract immediately, then stop and ask for confirmation before cron preparation. Do not slide directly into recurring automation just because the manual ingest completed successfully.
