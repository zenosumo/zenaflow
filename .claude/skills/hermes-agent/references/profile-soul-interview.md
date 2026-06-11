# Profile SOUL interview workflow

Use this when configuring a Hermes profile's `SOUL.md` or personality baseline by interviewing the user.

## Purpose

`SOUL.md` is the durable identity for the current `HERMES_HOME` / profile. It should define who the agent is, how it speaks, how it handles uncertainty/disagreement/ambiguity, and what stylistic behaviors to avoid. It should not become a dump of temporary project paths, one-off workflow details, ports, commands, or repo conventions unless the profile is explicitly a bounded worker whose identity includes those operational rules.

## Interview pattern

Ask one question at a time and wait for the user's answer before moving on. Do not produce the final `SOUL.md` until the user has answered enough to resolve the main design dimensions.

Recommended sequence:

1. Core identity / role
   - What is this profile fundamentally for?
   - Examples: personal assistant, research partner, coding assistant, technical operator, memory librarian, teacher, reviewer, fictional character coach.

2. Scope and boundaries
   - What topics or tasks should it handle?
   - What should it redirect or refuse?
   - For sensitive domains, encode safe role boundaries as behavior, not repetitive disclaimers.

3. Tone and emotional posture
   - Warm vs direct, playful vs formal, gentle vs intense, concise vs exploratory.
   - Ask for specific terms of address or terms of endearment only if relevant.

4. Advice / output style
   - Concise vs explanatory, examples-first vs analysis-first, ask-context-first vs best-guess-first.
   - Capture exact formatting preferences when the user gives them. Example: if the user asks for direct reply text, do not preface with labels like "Say this:"; provide the usable line immediately, then a short explanation only if requested or specified.

5. Language behavior
   - Should replies follow the user's chat language?
   - If the profile generates dialogue in one language and explains in another, explicitly distinguish the "scene/output language" from the "explanation language".

6. Context sources
   - Should the profile consult memory, a vault, repo, notes, or external docs before replying?
   - If yes, define whether to cite those sources, mention them only when useful, or silently use them as guidance.
   - A good rule for second-brain/vault-backed assistants: consult the source first, then mediate through judgment and emotional intelligence; do not copy-paste a solution from notes.

7. Missing context
   - Decide when to ask a clarifying question vs produce a best-effort answer.
   - Prefer the minimum needed question, not an interrogation.

8. Memory policy
   - Decide whether the profile may save stable preferences in its own memory, rely on a separate source of truth, ask before saving, or avoid memory.

## Drafting guidelines

- Keep the final `SOUL.md` stable, broad, and identity-focused.
- Use short sections: Identity, Scope, Voice, Advice Style, Language, Context Sources, Boundaries, Defaults.
- If a profile has a working directory with an `AGENTS.md`, include an explicit precedence sentence from the main skill: either SOUL overrides AGENTS.md or SOUL wins while AGENTS.md provides data-domain context.
- Do not repeat obvious assistant defaults. Add behavior that actually changes the profile.
- Avoid cluttering normal replies with repeated disclaimers when the boundary can be built into the role framing; reserve explicit redirection for requests that clearly leave the allowed role.

## Verification

After writing or editing the profile `SOUL.md`:

1. Read it back or summarize the exact behavior it encodes.
2. Restart the profile gateway or tell the user to start a fresh session so the new identity is loaded.
3. Optionally run a short test prompt against the profile to confirm tone, formatting, language behavior, and context-source behavior.