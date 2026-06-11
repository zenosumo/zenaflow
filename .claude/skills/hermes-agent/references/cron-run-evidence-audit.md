# Cron Run Evidence Audit

Use this when a user says a Hermes profile cron job should have run but repo/app effects are missing.

Goal: prove whether the scheduler fired, whether the agent completed, and whether the target side effect happened. Do not rely on `last_status: ok` alone.

## Evidence sequence

1. Confirm the exact profile and job identity:
   - `hermes profile show <profile>`
   - `hermes -p <profile> cron list --all`
   - `hermes -p <profile> cron status`
   - Inspect `<profile-home>/cron/jobs.json` for `last_run_at`, `last_status`, `next_run_at`, `workdir`, `deliver`, and `updated_at`.

2. Inspect durable cron output:
   - `<profile-home>/cron/output/<job_id>/<timestamp>.md`
   - This file contains the prompt and final response. Treat it as the primary user-facing evidence for what the cron run reported.

3. Inspect the session transcript when output is ambiguous:
   - `<profile-home>/sessions/session_cron_<job_id>_*.json`
   - Look for failing tool outputs, final summary, and any operational blockers that still ended with a normal text response.

4. Inspect profile logs:
   - `<profile-home>/logs/agent.log` for API calls, tool errors, and `cron.scheduler` completion lines.
   - `<profile-home>/logs/gateway.log` for gateway startup, cron ticker startup, platform conflicts, permission warnings, and shutdowns.

5. Verify target side effects directly:
   - For repo-writing jobs: `git status --short --branch`, recent commits, relevant file mtimes, expected log/index updates, queue counts, and uncommitted diffs.
   - For push-dependent jobs: test the same operation as the runtime user, not as root/current shell. A root shell may have SSH agent credentials that the gateway/cron user lacks.

## Interpretation pitfalls

- `last_status: ok` means the agent process produced a final response successfully. It does not prove the business task succeeded.
- Gateway log may be quiet during individual ticks; `agent.log`, cron output markdown, and session JSON usually carry the detailed evidence.
- A cron run can make only an operational/error note in the target repo and still do no real ingest/sync work.
- Always distinguish: scheduler fired, agent completed, target task succeeded, commit created, push succeeded.

## Recommended final report shape

- State whether the cron fired.
- Quote job id, schedule, last run time, and last status.
- Quote the cron output summary or final response.
- Quote the exact blocker from session/logs.
- State observed target-side effects and missing expected effects.
- Give the smallest concrete fix or next verification step.