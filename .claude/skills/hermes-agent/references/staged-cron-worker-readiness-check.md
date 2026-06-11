# Staged cron-worker readiness check

Use this when a user wants to validate a Hermes worker profile and cron job before allowing it to run. The key pattern is staged gating: inspect first, wait for confirmation, run one controlled manual prompt, wait again, then prepare or resume cron.

## Phase 1 — readiness check only

Do not trigger the worker prompt and do not run `hermes cron run`.

1. Inspect profile identity and config:
   - `hermes profile show <profile>`
   - `hermes -p <profile> tools list`
   - `hermes -p <profile> gateway status`
   - relevant config: `model`, `terminal.cwd`, `memory`, `security.redact_secrets`, `approvals.cron_mode`, `cron.max_parallel_jobs`.
2. Inspect existing cron jobs:
   - `hermes -p <profile> cron list --all`
   - If an existing job is active and could tick during the readiness window, pause it immediately and tell the user. This is not “starting” the job; it prevents accidental start while the user is asking for a check-only pass.
3. Inspect the worker contract:
   - Read the profile `SOUL.md`.
   - Confirm it states precedence vs cwd `AGENTS.md` if both are injected.
   - Confirm allowed reads/writes, trigger model, no-op behavior, failure handling, commit/push policy, and summary format.
4. Inspect the workdir/repo without modifying content:
   - Git branch, ahead/behind, remote reachability, dirty tree, stashes.
   - Fetch/pull latest before declaring the repo state final. If the tree is dirty, distinguish user/source-of-truth changes from local readiness edits the agent just made.
   - Required runtime directories and structural docs.
   - Pending queue counts and quick strict-filter counts if the worker processes files.
5. Identify blockers before any manual run:
   - Dirty tree that the worker would stash on pre-flight. Do not overstate this as a blocker until after fetching/pulling and checking whether the dirty files are agent-made readiness edits that should be reverted or committed explicitly.
   - Existing active cron job that would run before confirmation. If the user asks to "start clean" or "clear cron jobs", remove all existing jobs rather than merely pausing them; list/verify that no jobs remain.
   - Profile model/provider mismatch or stale cron errors from a prior provider.
   - Missing required files that the worker assumes exist.
   - Missing empty runtime directories are not automatically blockers when the worker contract creates them during pre-flight (e.g. `mkdir -p raw/inbox raw/processed raw/skipped raw/quarantine raw/assets`). Report them as generated-as-needed, not as Git blockers, unless the worker explicitly requires them to be committed.
   - Cloned messaging/API env vars in a cron-only profile that could activate platforms after a restart. Blank/disable inherited platform env vars and verify logs/status show "No messaging platforms enabled" for a cron-only worker.

## Phase 2 — controlled manual prompt

Proceed only after user confirmation.

Run a single bounded prompt through the worker profile, not the scheduler, with a deliberately small scope if possible. After it completes, inspect:

- final response / session output
- git status and commits created
- log/followups/stats updates
- moved/skipped/quarantined source files
- push result or local backlog

Additional validation pitfalls for repo-writing workers:

- Verify that committed metadata is actually knowable at write time. A file cannot reliably contain the final SHA of the same commit that writes it; prefer `commit=pending` in committed logs and report actual SHAs in the returned operational summary, or use a separate follow-up correction commit intentionally.
- If the worker says it processed the "oldest" file, verify the ordering rule is deterministic. When many queued files share the same mtime, the worker contract should specify a tie-breaker such as filename ascending.
- If the worker contract is missing either of the above, patch the worker profile contract before cron rollout rather than relying on operator memory.

Wait for user confirmation again before enabling recurring automation.

## Phase 3 — cron preparation

Only after the manual prompt succeeds:

- Prefer updating/resuming an existing cron job over creating a duplicate.
- Ensure schedule, prompt, delivery, workdir/toolsets/model override are intentional.
- Keep cron `max_parallel_jobs: 1` for single-writer repo workers unless the design explicitly supports concurrency.
- Resume or create the cron job, then list jobs to verify state.

## Reporting style

For staged rollout requests, keep the final report clearly separated by phase. End Phase 1 with the exact next action that requires user confirmation. Do not drift into Phase 2 or Phase 3 without that confirmation.