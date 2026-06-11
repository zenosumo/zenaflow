# Auditing a Hermes Profile Against an External Spec

Procedure for reviewing an existing Hermes profile's `SOUL.md` + `config.yaml` + skill bundle against an external specification (architecture plan, schema document, runbook). Used in the field for `memento-ingest` vs an `argo-lazarus-second-brain-v3.md` architecture plan; generalizes to any profile review.

Companion to `references/cron-worker-profile-design-checklist.md` (the menu of design dimensions) and `templates/cron-worker-profile-soul.md` (the skeleton).

## When to use

- User says "audit / critique / review this profile."
- A profile was created by a prior session and the user wants to verify it before first cron tick.
- A spec was updated and you need to check the worker still complies.
- User asks "is this sound?" / "what am I missing?" — that's a request for this procedure, not a single answer.

## What you'll need to read

For a thorough audit, gather these before producing any critique:

1. **The architecture plan(s)** the profile is supposed to implement. Read all of them, including superseded versions — the older version often contains rationale that the newer one assumes you've internalized.
2. **The profile's `SOUL.md`** — the agent's operating contract.
3. **The profile's `config.yaml`** — especially `terminal.cwd`, `memory.*`, `cron.*`, `agent.*` timeouts, enabled toolsets, model/provider.
4. **The profile's `MEMORY.md` / `USER.md`** if memory is enabled — these may contradict the SOUL or carry stale instructions.
5. **The profile's bundled skills** (`<profile>/skills/`) — large skill bundles slow the planner and risk pulling irrelevant skills.
6. **The data directory the profile operates on** (`terminal.cwd`) — especially any `AGENTS.md` there, since Hermes auto-injects it into the system prompt. Schema files, existing content layout, sample inputs.
7. **The cron job (if any)** that triggers the profile — schedule, prompt, attached skills, `enabled_toolsets`, `workdir`.
8. **The launcher script / alias** in `~/.local/bin/<profile>` — confirms how the profile is actually invoked (often reveals the profile dir name typo case).

Spend the upfront read budget. A confident audit needs all of it.

## Procedure

### Pass 1 — Coverage against the spec

For each obligation in the spec, classify the profile's coverage:

- ✓ Fully covered — SOUL or config says exactly what the spec demands.
- ◑ Partial — SOUL touches the area but weakens the obligation ("when practical" replacing a mandatory step, generic language replacing specific enumeration).
- ✗ Missing — spec says X, SOUL doesn't.

Produce a compact table (markdown if rendering, plain text if CLI). Group by section of the spec, not by section of SOUL.

Look specifically for:
- Mandatory schema fields the spec enumerates but SOUL doesn't (`level:`, typed relations, provenance frontmatter, source-type-specific enrichment like YouTube channel).
- Sequence/order obligations ("read X first, then write Y, then update Z") — SOUL often paraphrases these and drops a step.
- Coordination rules (lock files, git workflow, multi-writer rules).
- Failure-mode obligations (what happens on parse error, on conflict, on duplicate).

### Pass 2 — Second-pass for missed items

The first pass tends to find spec-listed gaps. The second pass finds *interaction* gaps that no individual section of the spec called out.

Walk through this lens explicitly: "what hasn't been considered?" Categories to scan:

- **Concurrency / re-entrancy**: parallel ticks, overlapping writers, dirty-tree-on-restart, committed-but-unpushed recovery.
- **Idempotency / dedup**: how does the worker recognize duplicate inputs? Is the recognition signal robust to legitimate drift in the input source?
- **Input safety**: file size caps, encoding filters, symlink containment, age-since-last-write (mid-write protection), secret patterns.
- **Failure & recovery**: per-source vs per-batch transactions, quarantine for repeat-failures, per-source timeout vs gateway timeout interaction.
- **Performance / scaling**: read-budget per item, log/index rotation, byte caps vs count caps.
- **Schema enforcement**: validation before write, taxonomy drift, entity dedup.
- **Observability**: cron output capture verification, counter file for falsification triggers, error prefix in followups.
- **Doc/meta**: SOUL-vs-AGENTS precedence when cwd auto-injects, living-document clause, skill bundle trim, model and cadence choices.

Use `references/cron-worker-profile-design-checklist.md` as the menu — anything in there that SOUL doesn't address is a candidate gap.

### Pass 3 — Interactive per-item review with the user

Don't dump the full critique and ask "thoughts?" Instead, go through items one at a time, present the trade-off, give a recommendation, let the user decide. This:

- Forces explicit decisions (the user can't shrug at "the whole thing").
- Catches consistency interactions (the user's choice on item N may conflict with their earlier choice on item M; you can flag it immediately).
- Produces a documented decision record (this transcript becomes the audit log).

For each item, present:
1. The concern in 1-2 sentences.
2. 2-4 concrete options (the `clarify` tool's choice list is the right shape).
3. Your recommendation with reasoning.
4. Note any cross-item interactions the user should consider before deciding.

### Pass 4 — Consistency check after each decision

After each user decision, mentally diff against earlier decisions in this session. Common conflict patterns:

- User picked stricter behavior on a related item earlier, looser now (or vice-versa) — surface the inconsistency.
- Item N's choice depends on item M's numbers (e.g. per-source timeout × batch size vs gateway timeout). Run the math, push back if it doesn't fit.
- Item N undermines a Stage-1/optional-fields decision from item M (mandating typed relations after making `level:` optional, for example).

When you spot a conflict, pause the sequence and offer a focused clarify with options to reconcile (raise the timeout, lower the batch, switch the optional/mandatory choice). Don't just note it and move on.

### Pass 5 — Produce the final settled list

After all items are decided, produce a single consolidated list grouped by category, ready to consume as a diff. This list IS the audit deliverable. Each item is one line stating the chosen behavior.

Save the list before producing the diff; if the user wants to revisit a choice, you have the canonical version.

## What NOT to do

- **Don't fix the diff first.** Audit is decision-making; writing the SOUL patches is a downstream task. Mixing them confuses both.
- **Don't omit "do nothing" as an option.** Some items genuinely don't need fixing for the user's volume/scope. The honest recommendation is sometimes "defer until data tells us we need it."
- **Don't recommend without acknowledging the trade-off.** Every recommendation has a downside; state it. "I recommend X, downside is Y" is more useful than just "X."
- **Don't anchor on the spec.** The spec may have over-engineered for an enterprise scale the user doesn't have. Plan v3 §1 explicitly downscoped from v2 — your audit should respect that scope statement and not re-impose the larger frame. Quote the scope statement back at yourself if you catch yourself reaching for it.
- **Don't capture session-specific fixes as durable skill rules.** This is an *audit procedure* skill; what the user chose for memento-ingest stays in this session's transcript, not in this skill file.

## Output shape

A good audit session produces:

1. Pass 1 coverage table (spec obligations × profile coverage).
2. Pass 2 second-pass list (interaction gaps, grouped by category).
3. Interactive per-item resolution log (one decision per item, with reasoning).
4. Consolidated settled list (the audit deliverable).
5. Optionally: the SOUL.md / config.yaml diff, as a separate downstream task.

If the user only asks for "critique" without "fix," stop at #4 and offer to produce the diff.

## Worked example

The first run of this procedure produced the memento-ingest audit. See conversation transcript ("examine other similar checks you overlook..." through the 42-item walk-through). Items numbered 1-42 there map to the categories in `references/cron-worker-profile-design-checklist.md`. The user-corrections during that walk-through (rejecting fuzzy dedup in favor of filename-based, downgrading mandatory schema fields to optional, raising the gateway timeout vs lowering the per-source timeout, choosing all-or-nothing batches over per-source transactions) are documented in the transcript and shouldn't be back-imported as defaults — different users will choose differently.
