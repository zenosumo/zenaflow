# Repo-writing cron worker log finalization pitfall

Session pattern: a cron-only Hermes profile manually ingested multiple Markdown sources into a Git-backed vault. The worker created per-source commits correctly, but `log.md` looked wrong afterward: new machine log lines were appended directly after an older prose section, and per-source lines still showed `commit=pending` even though the source commits existed.

## Pitfall

For repo-writing workers that commit each source transaction independently, the actual source commit SHA is only known after each source commit succeeds. If the worker writes `commit=pending` during the source transaction and never performs an end-of-tick metadata finalization, the repo is technically updated but human auditability suffers.

A second pitfall is log readability: appending machine log lines directly after a previous narrative/prose section makes it look like `log.md` was not updated or was malformed.

## Preferred contract shape

Add explicit log section and finalization rules to the worker profile/SOUL:

```text
Append to log.md:
- Ensure `log.md` contains a blank line and heading `## [YYYY-MM-DD] ingest activity` for the current UTC date.
- If the heading is missing, append it before today's first ingest/tick-summary line.
- Do not append machine log lines directly onto the end of an older prose paragraph or old dated section.
- Under that heading, append one per-source line initially using `commit=pending`.

After each successful source commit:
- Store the actual short SHA in an in-memory tick map keyed by source filename.

End-of-tick:
- Before the final meta commit, rewrite this tick's `commit=pending` source lines to the actual short SHAs.
- No `commit=pending` lines from the current tick may remain when the tick exits successfully.
- Commit finalized `log.md`, `wiki/_meta/stats.json`, `followups.md` if changed, and any other tick-level metadata in a final metadata commit.
- Push only after source commits and the final metadata commit exist.
```

## Verification steps

After a manual smoke test and before cron rollout:

1. `git log --oneline -- log.md` should show source commits and/or the final metadata commit touching `log.md`.
2. `git diff --name-only <pre-run-head>..HEAD` should include `log.md` when ingest happened.
3. `tail -n 40 log.md` should show a current `## [YYYY-MM-DD] ingest activity` section.
4. No successful current-tick source line should contain `commit=pending`.
5. The commit fields in `log.md` should match real source transaction short SHAs from `git log --oneline`.
6. `git status --porcelain` should be empty and `origin/<branch>...HEAD` should be 0/0 after push.

## Operator correction pattern

If a smoke test left log metadata readable but incomplete:

1. Patch `log.md` to add the dated ingest heading and replace current-tick `commit=pending` with actual source SHAs.
2. Commit and push that correction.
3. Patch the worker profile contract immediately so future ticks finalize `log.md` automatically.
4. Do not create or resume cron until the corrected contract is verified.
