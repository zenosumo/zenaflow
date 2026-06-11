# Manual profile ingest verification

Use this when manually smoke-testing a repo-writing Hermes profile before enabling cron.

## Lessons captured

- Match the manual prompt to the intended batch size. If the worker SOUL says a soft cap of 3 and the user approves a 3-file smoke test, do not add a narrower "at most one" bound. Operator prompt bounds override the worker's normal batching behavior.
- For a corrective rerun after an under-batched test, run only the missing count when that preserves the original intent. Example: if 1 of 3 was already ingested, run exactly 2 more; if the user explicitly says to redo the step and ingest 3 now, run exactly 3 additional sources.
- Verify actual model/profile usage from profile-local evidence, not only dashboards. Good evidence includes:
  - profile-local session JSON under `$HERMES_HOME/sessions/`
  - profile-local `logs/agent.log` lines for the exact `session_id`
  - state DB session row fields such as `model`, `billing_provider`, and `billing_base_url`
  - command invocation using `hermes -p <profile>`
- Dashboards can be stale or scoped to a different profile/account. Treat dashboard disagreement as a prompt to inspect logs, not as final truth.
- After the manual profile run, verify the repo is truly clean. Some workers may commit source transactions and metadata while leaving allowed operational notes such as `followups.md` modified. Commit/push or deliberately roll back those allowed changes before reporting success.

## Minimal verification checklist

1. Pre-run: clean worktree, fetch/pull/rebase current branch, count pending and processed files.
2. Run: invoke the exact profile with `hermes -p <profile>` and a prompt whose batch count matches the approved test.
3. Model/profile: inspect the newest profile-local session JSON and agent log for `session_id`, `model`, `provider`, `platform`, and API call lines.
4. Data result: verify source counts changed by the expected amount and list the processed filenames.
5. Repo result: inspect recent commits, push state, `git status --porcelain`, and ahead/behind origin.
6. Automation boundary: verify cron jobs were not created or resumed unless the user approved the cron step.
