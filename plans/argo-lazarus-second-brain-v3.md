# Argo + Lazarus Second Brain Architecture Plan v3

Date: 2026-05-17
Status: architecture/design plan, supersedes v2
Vault name: Memento
Repo: github.com:zenosumo/memento.git
Local path: /Users/pocmior/Vaults/Memento

## 0. What changed since v2

v3 is v2 plus the lessons surfaced during the Jsong/Karpathy comparison and the
Karpathy gist comment thread review. v2 architecture remains the source of
truth for §§5–17, §19, §20. v3 supersedes v2 on:

- coordination model (no lock files; spatial write separation + lazy git)
- Obsidian's role (explicit: reader/editor only, not system)
- staged rollout with falsification triggers (don't pre-populate empty folders)
- pre-write identity check (dedup before create)
- typed relationships (contradicts / extends / supersedes / related)
- hierarchy/level field (prevent flat-graph collapse)
- raw-source provenance via sha256
- tiered lint (auto-fix / propose-fix / human-only)
- triage-before-write for relational domains (`people/`, `companies/`)
- honest scope statement (this is a personal vault, not org-scale IR)

Refer to v2 for any topic not addressed here.

## 1. Scope statement (honest framing)

Memento is a personal second brain for one user. It is not an
enterprise-grade information retrieval system. It does not need to
scale to 10k sources or multiple writers. It needs to:

- absorb ~5–50 Web Clipper sources per week
- capture ~3–20 journal events per day via Telegram
- maintain ~10–200 person/company profiles over years
- track ~5–20 active/incubating projects

If any of those volumes 10x, revisit the architecture. The Markdown +
Git foundation is correct up to roughly low-thousands of notes; beyond
that, derived indexes or a DB cache become necessary (see v2 §11).

The skeptical critique that "LLM wikis don't scale" applies to
organizational knowledge bases, not to personal vaults of this size.
Acknowledge it; don't oversell the system to yourself.

## 2. Coordination model (replaces v2 §18)

Drop the lock-file requirement. Replace with spatial write separation +
lazy git.

### Write zones

Lazarus (macOS) writes only to:
- `raw/inbox/` (via Obsidian Web Clipper, indirectly)
- `media/inbox/` (manual drops)
- human edits anywhere in Obsidian (low frequency, opportunistic)

Argo (VPS) writes to:
- everything else: `wiki/`, `people/`, `companies/`, `projects/`,
  `journal/`, `raw/processed/`, `media/<sorted>/`, `index.md`, `log.md`,
  `followups.md`, all sub-`index.md` files

Overlap is bounded to:
- `index.md` and `log.md` (both sides may touch)
- human-edited files that Argo later regenerates (rare)

### The one git rule

Both sides follow: **fetch, rebase-pull, write, commit, push; on push
failure rebase-pull once and retry; on second failure surface to user.**

```bash
git fetch origin
git rebase origin/main || { git rebase --abort; exit 1; }
# ... do the work ...
git add -A && git commit -m "..."
git push || (git fetch origin && git rebase origin/main && git push) || exit 1
```

This is the only piece of plumbing Memento needs for coordination.
No locks, no queues, no message brokers.

### Why this works

Different paths → no real conflicts. The only files both sides touch
are `index.md` and `log.md`, both of which are append-style and resolve
as trivial 3-way merges 95% of the time. The remaining 5% is a
10-second manual resolve and is acceptable at this volume.

## 3. Obsidian's role (new clause)

Obsidian is the **reader, editor, and capture UI** for Lazarus. It is
not the system, not the writer, not the sync layer.

- System: Markdown + YAML frontmatter + Git
- Writer: Argo (primary), Lazarus (rare, on request)
- Sync: GitHub
- Reader/editor: Obsidian (graph view, backlinks, Dataview, light edits)
- Capture: Obsidian Web Clipper (browser → `raw/inbox/web-clips/`)

Falsification triggers for dropping Obsidian:
- not opened for ≥2 weeks and not missed
- frontmatter complexity exceeds what Obsidian renders cleanly
- vault > ~50k notes or media > ~5 GB (re-evaluate, may keep for graph only)

Agents must not read or modify anything under `.obsidian/`. It is
Obsidian client state, not vault content.

## 4. Staged rollout (new clause)

Do not pre-populate empty folders. Each stage must justify the next.

### Stage 1 — Jsong slice (week 1, current state of repo)

In place:
- `raw/inbox/` (Web Clipper destination — currently `raw/`; rename when convenient)
- `raw/processed/`, `raw/assets/`
- `wiki/`
- `AGENTS.md`, `index.md`, `log.md`, `.gitignore`
- Argo as single writer, ingest + query + lint operations only
- Obsidian on Mac for reading and capture

Falsification trigger to stop here permanently:
- after 30 days, < 10 sources ingested → architecture too heavy, just
  keep using raw clippings

### Stage 2 — journal + companies (weeks 2–3)

Add when stage-1 ingest is working and Telegram capture is wired up:
- `journal/events/YYYY/MM/`
- `journal/daily/YYYY/MM/`
- `companies/profiles/`, `companies/interactions/`, `companies/opportunities/`
- `followups.md`
- `SCHEMA.md` (split from AGENTS.md when AGENTS.md exceeds ~150 lines)
- frontmatter conventions for journal-event and company per v2 §20

Why companies before people: highest ROI for the user's QA/CV use case;
people emerges from company captures anyway.

Falsification trigger to skip stage 3:
- after 30 days in stage 2, `companies/profiles/` has < 5 entries →
  capture pressure does not justify the schema

### Stage 3 — people + projects (week 4+)

Add when stage 2 has measurable usage:
- `people/profiles/`, `people/interactions/`
- `projects/incubating/`, `projects/active/`, `projects/paused/`, `projects/archived/`
- `projects/templates/`
- project validation gate per v2 §14 (kill criteria, confidence fields)
- frontmatter conventions for person, interaction, project per v2 §20

### Deferred (do not build until justified)

- `workflows/*.md` as separate files (until AGENTS.md becomes unwieldy)
- `templates/*.md` (until inline template suggestions in AGENTS.md break down)
- derived indexes (`indexes/graph.json`, etc.) — only if Dataview query
  pain demands them
- Git LFS — only if repo > 1 GB or single push > 50 MB
- Static-site publishing surface (Quartz / MkDocs) for a curated public
  subset — only if portfolio/credibility need emerges
- MongoDB or any DB layer — only if Markdown query latency becomes
  intolerable, and only as an index/cache derived from Markdown

## 5. Pre-write identity check (new, supersedes v2 §9 dedup intent)

Before Argo creates a new note in `people/profiles/` or
`companies/profiles/`:

1. Fuzzy-match candidate name against existing profiles (slug,
   aliases, frontmatter `name`, frontmatter `aliases[]`).
2. Match modes:
   - exact slug → block creation, update existing
   - fuzzy name match (Levenshtein < 3 or shared multi-word substring)
     → emit triage report, ask user
   - no match → create new
3. Triage report format (Telegram message from Argo):
   ```
   New company candidate: "Finbank S.p.A."
   Possible existing match: companies/profiles/finbank.md (Finbank, Italy)
   Reply: merge | create-new | skip
   ```
4. On `merge`: update existing profile + append alias.
5. On `create-new`: create with cross-link `see_also: [company_finbank]`.
6. On `skip`: log to `followups.md` and do not write.

Applies to: people, companies. Optional for wiki concept/entity pages
(lower stakes). Mandatory for relational domains.

## 6. Typed relationships (extends v2 §11)

Wikilinks remain for human navigation. Stable IDs remain for structured
search. Add explicit relationship typing in frontmatter — do not
collapse everything into a single `related: []`.

Standard relation types:

```yaml
related: []        # generic association
extends: []        # this page builds on / refines another
contradicts: []    # this page disagrees with another
supersedes: []     # this page replaces an older claim/page
contained_in: []   # this is a sub-page of a larger topic
contains: []       # inverse: this is a parent topic
see_also: []       # adjacent but not derived
```

When Argo synthesizes from a source that contradicts an existing wiki
claim, it must:
1. Mark `contradicts: [page_id]` on the new claim.
2. Mark `contradicted_by: [new_page_id]` on the older claim (do not
   silently overwrite).
3. Append to `followups.md`: contradiction requires human resolution.

Cheap to add now in frontmatter conventions; painful to retrofit later.

## 7. Hierarchy level field (new)

Add to every wiki note frontmatter:

```yaml
level: source | claim | concept | topic | map
```

- **source**: a `wiki/sources/*.md` summary of one raw artifact
- **claim**: a single citable proposition extractable from sources
- **concept**: a synthesized idea drawing on multiple claims
- **topic**: a broad area containing many concepts
- **map**: a navigation/index page for a topic cluster

Purpose: prevents flat-graph collapse where "Career Strategy" and
"Marco's preferred coffee" appear at the same visual weight in the
graph view. Enables Dataview queries like "show all topic-level pages"
or "concepts with no supporting claims yet."

## 8. Raw source provenance (new)

Every file in `raw/processed/` carries body-sha256 in frontmatter:

```yaml
---
source: web-clipper
url: https://...
clipped_at: 2026-05-17T14:30:00Z
processed_at: 2026-05-17T14:35:00Z
body_sha256: <64-char-hex>
---
```

Lint workflow can then detect:
- accidental modification of "immutable" processed sources
- re-clips of the same URL that produced different content (source drift)
- duplicate clips with identical content

Cheap, defensible audit trail. Computed body-only (excludes
frontmatter) so re-adding metadata does not invalidate the hash.

## 9. Tiered lint (extends v2 §lint mention)

Lint is not monolithic. Three tiers, applied in order:

### Auto-fix (no LLM, no human review)

- broken wikilink where target slug exists (case mismatch, spaces vs hyphens)
- missing entry in `index.md` for a file that exists
- malformed YAML where fix is mechanical (trailing comma, unquoted colon in value)
- stable-ID missing from frontmatter where slug is derivable

Argo commits with prefix `lint: auto-fix`.

### Propose-fix (LLM, queued for review)

- orphan page (no inbound links) — propose either delete or linking source
- concept page that could be split into two
- stale claim (source-date > 12 months and topic is fast-moving)
- duplicate-candidate pages (high name similarity, distinct content)

Argo writes proposals to `followups.md` and does not commit changes.

### Flag-only (human resolution required)

- contradiction between two claims
- identity ambiguity (two profiles that may be the same person/company)
- broken sha256 on a processed raw file
- frontmatter schema violation Argo can't repair

Argo writes to `followups.md` with severity flag; no edits.

Lint runs:
- on every ingest (auto-fix only, fast path)
- nightly cron (all three tiers)
- on demand via Telegram `lint:` prefix

## 10. AGENTS.md as living document (Jsong steal)

AGENTS.md is not a static spec written once. It is the operating
manual Argo and Lazarus follow, and it co-evolves with real usage.

Update rules:
- When Argo discovers a recurring pattern not covered by AGENTS.md, it
  must propose an addition to `followups.md` rather than silently
  inventing one.
- When Lazarus reviews a series of Argo writes and identifies a
  convention drift, Lazarus patches AGENTS.md.
- Major schema changes (new note type, new folder, new frontmatter
  field) go in SCHEMA.md once SCHEMA.md exists; behavior rules stay in
  AGENTS.md.
- Every AGENTS.md change is a normal git commit; history is the audit log.

## 11. Triage-before-write for relational domains (new)

For high-stakes writes — `people/`, `companies/`, `companies/opportunities/`,
project status changes — Argo does not write blindly. Sequence:

1. Compute the diff (new file vs existing, or update vs current).
2. Emit a triage report to Telegram, max 5 lines:
   ```
   companies/profiles/finbank.md
   + add pain_signal: flaky Playwright tests
   + add contact: person_marco_rossi (QA Lead)
   + bump open_loops: 0 → 1
   Reply: ok | edit | skip
   ```
3. On `ok` → write and commit.
4. On `edit` → user provides correction, Argo applies.
5. On `skip` → log to `followups.md`, no write.

Applies to: people, companies, project status transitions
(incubating → active, especially).

Does NOT apply to: journal events (always capture immediately, ask
follow-ups after), wiki ingest (lower stakes, easier to undo), raw
processing (mechanical).

Rationale: nowissan's identity-failure-mode observation. Stake is
proportional to relational consequence.

## 12. Falsification triggers (consolidated)

Track these explicitly. Review monthly. They prevent sunk-cost
attachment to architecture that isn't earning its weight.

| Trigger | If true after… | Action |
|---|---|---|
| < 10 sources ingested | 30 days | stop at stage 1, treat as raw-only archive |
| < 5 companies tracked | 30 days in stage 2 | skip people/projects, archive companies/ |
| < 30 journal events | 30 days | reconsider whether Telegram capture matches life |
| Obsidian unopened | 2 weeks | drop Obsidian, keep vault as raw repo |
| Argo writes < 3/week | 30 days | reduce schema, single-agent mode |
| YAML parse failures > 5/week | rolling | tighten lint, simplify frontmatter |
| Repo > 1 GB | any time | introduce Git LFS for media |
| Push collision > 1/week | rolling | tighten the rebase-retry rule or split repo |

## 13. Updated frontmatter additions (extends v2 §20)

Add to existing shapes:

### Any wiki page
```yaml
level: source | claim | concept | topic | map
extends: []
contradicts: []
contradicted_by: []
supersedes: []
superseded_by: []
see_also: []
```

### Raw processed source
```yaml
source: web-clipper | manual | youtube | rss | telegram-paste
url:
clipped_at:
processed_at:
body_sha256:
```

### Person / company profile
```yaml
aliases: []          # add: critical for dedup
canonical: true      # true if this is the merged-target; false if see_also stub
merged_from: []      # IDs of previously-separate profiles merged into this one
```

## 14. What Memento explicitly is not

To prevent scope creep:

- Not a public knowledge base. No public URL by default.
- Not a CRM replacement. `companies/` and `people/` are personal
  records, not sales pipeline.
- Not a project management tool. `projects/` tracks thinking and
  validation, not tasks. Use a separate todo system for tasks.
- Not a chat history archive. Journal events are user-curated, not
  raw Telegram dumps.
- Not a backup of external sources. `raw/processed/` is for sources
  the user actively cared about enough to clip.
- Not a multi-user vault. Argo and Lazarus are agents acting on
  behalf of one user. No ACLs, no permissions.
- Not real-time. Eventual consistency via git push/pull is fine.
  Captures should never block on agent response.

## 15. Open questions for v3 implementation

1. Telegram bot persona and exact prefix vocabulary (deferred from v2 §21).
2. Where Argo runs: `/opt/memento` or `/opt/vault`? Recommend
   `/opt/memento` to match repo name.
3. Whether daily summary runs on cron or on demand only.
4. Where `followups.md` gets reviewed — Telegram digest each morning?
   Or only when user asks?
5. How Argo authenticates to GitHub on the VPS — deploy key vs PAT.
   Recommend deploy key with write access, single-purpose.
6. Whether Argo should self-heal AGENTS.md (auto-propose patches) or
   only Lazarus does (safer; recommended for first 90 days).

## 16. Design summary

Memento is a private GitHub-backed Markdown vault, read in Obsidian on
macOS, written by Argo on a VPS, planned and reviewed by Lazarus.

Coordination is spatial separation + lazy git, not locks. Obsidian is
the IDE, Argo is the programmer, the vault is the codebase, GitHub is
the version control.

Build in stages. Justify each stage with usage. Use falsification
triggers to prevent over-engineering.

For relational domains (people, companies), check identity before
write and triage diffs through Telegram. For wiki, ingest freely but
type relationships explicitly so the graph does not collapse to flat
"related" edges.

Treat lint as three operations, not one: auto-fix mechanically,
propose-fix to a review queue, flag contradictions for humans.

Keep the system honest. It is a personal vault, not an enterprise
search platform. Scope statement and falsification triggers are the
guardrails.
