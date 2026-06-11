# Interactive profile SOUL setup

Use this when a user asks to configure a Hermes profile's SOUL/personality and wants to answer questions step by step.

## Workflow

1. Load the `hermes-agent` skill first.
2. Check the relevant Hermes docs if the user explicitly asks for documentation grounding. The key concepts:
   - Profile SOUL lives in the profile home: `$HERMES_HOME/SOUL.md`.
   - For a profile named `<profile>`, locate it with `hermes -p <profile> config path` and replace `config.yaml` with `SOUL.md`.
   - `SOUL.md` is the primary identity in system-prompt slot #1.
   - `/personality` is a temporary/session overlay; SOUL.md is the durable baseline identity.
   - SOUL is for identity, voice, durable interaction style, ambiguity/disagreement handling; project/repo commands belong in `AGENTS.md` or project context.
3. Ask one question at a time and wait after each answer. Good question sequence:
   - Core role/identity.
   - Tone and emotional temperature.
   - Terms of address / endearments, if relevant.
   - Required context sources, e.g. an Obsidian vault or repo.
   - Boundary style: explicit reminders vs built-in framing vs redirection.
   - Advice/answer format.
   - Language rules, including separating user-chat language from output/dialogue language.
   - Missing-context behavior.
   - Memory behavior.
   - Tool boundaries.
   - What to do when the required context source has no relevant info.
4. Summarize the accumulated spec occasionally so the user can correct it.
5. Write the profile `SOUL.md` with clear sections such as Identity, Voice, Context Source, Response Style, Language, Boundaries, Memory, Defaults.
6. If the user wants tool boundaries, update the profile toolsets to match. Be careful not to disable tools required by the gateway itself; profile toolset changes affect future sessions, not the already-running gateway's loaded prompt/tools.
7. Restart the profile gateway so new SOUL/tool settings take effect, then verify status and recent gateway log lines.

## Safety / boundary pattern

If the requested persona involves morally bad, manipulative, coercive, or exploitative behavior, keep the SOUL useful for fiction, improv, character writing, critique, or scene craft. Do not encode instructions that enable real-world exploitation. A good SOUL pattern is:

- Treat the domain as acting, storytelling, and improvisational scene work.
- Do not clutter normal fictional replies with repeated disclaimers if the user asked for built-in framing.
- If a request clearly moves outside fiction into real-world harm, redirect into scene craft, character motivation, dialogue, subtext, ethical acting analysis, or fictional consequences.

## Tool-bound context-source pattern

When a profile must always consult a local knowledge source before advice, put the requirement in SOUL and keep it operational:

```markdown
Before giving advice, always consult `<path>`.
Use it as emotional/contextual guidance, not as a script.
If it has no relevant information, answer anyway using best judgment and do not mention that it lacked context.
```

For a local Obsidian vault such as `/memento`, leave `file` and usually `terminal` enabled so the agent can inspect/search the vault. Disable web/browser if the user says the role should use the vault only.

## Example concise dialogue-answer format

For a profile that gives line/dialogue advice:

```markdown
When asked what to say or how to reply:
- If there is enough context, answer directly.
- If context is genuinely missing, ask only the minimum needed question.
- Do not use introductions like "Say this:".
- Start directly with the usable line.
- Then give a second short message explaining the expected effect and psychological implication.

Default format:
<direct usable line>

Effect: <very concise emotional/subtext explanation.>
```

## Verification commands

Inside a container/source checkout, prefer the checked-out entrypoint when available:

```bash
H=/opt/hermes/.venv/bin/hermes
SOUL=$($H -p <profile> config path | sed 's#/config.yaml$#/SOUL.md#')
$H profile show <profile>
$H -p <profile> tools list
$H -p <profile> gateway status
```

Manual gateway restart pattern when the gateway was started from the current agent as a tracked background process:

1. Poll/kill the tracked process with Hermes process tools if available.
2. Start `hermes -p <profile> gateway run` in background.
3. Verify `hermes -p <profile> gateway status` and log lines such as `Connected to Telegram` and `Gateway running with 1 platform(s)`.

If the gateway is managed outside the current session, use the appropriate `hermes -p <profile> gateway restart` / service/container restart path instead of killing an unknown process.