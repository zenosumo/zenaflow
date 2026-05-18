# Argo + Lazarus Second Brain Architecture Plan v2

Date: 2026-05-15
Status: architecture/design plan
Vault name: Memento

## 1. Purpose

Memento is the shared durable knowledge layer for the user's personal second brain.

The goal is not just to store notes. The goal is to create an operating system for:

- emerging knowledge and topics
- journal/event capture from real life
- people and relationship memory
- company/customer/employer intelligence
- projects that combine technical execution, business thinking, marketing, and validation
- raw source ingestion from Obsidian Web Clipper
- shared access between Argo and Lazarus

The vault should be understandable to the user in Obsidian, processable by agents as raw Markdown files, and synchronized through a private GitHub repository.

## 2. Naming and agent roles

There are two Hermes-based agents in the user's architecture, so they must be named distinctly.

### Lazarus

Lazarus is this local/planning/review assistant.

Primary responsibilities:

- architecture and planning
- manual inspection and review
- writing plans
- troubleshooting Argo
- improving rules, schemas, and workflows
- occasional direct vault processing only when explicitly asked

Lazarus should not be the default automated writer of Memento.

### Argo

Argo is the Hermes instance on SSH alias `zenaflow`.

Primary responsibilities:

- VPS always-on operator
- Telegram capture
- journal entries
- direct people entries
- direct company entries, CV/application tracking, and customer/prospect notes
- project entries
- raw Web Clipper ingestion
- daily and weekly summaries
- git pull / commit / push
- scheduled maintenance

Argo is the primary automated writer of Memento.

### Coordination principle

One automated writer. Many readers.

Argo is the default writer. Lazarus may write only when the user explicitly asks or when Argo is paused/unavailable.

GitHub is the synchronization and audit layer.

## 3. Source of truth

The source of truth is the Memento Obsidian vault in a private GitHub repository.

Do not treat either agent's internal memory as the source of truth for wiki knowledge, people records, projects, or journal history.

Agent memory is for compact durable facts about the user or environment.

Memento is for real knowledge and records.

## 4. Repository decision

Decision: store the whole Memento vault in one private GitHub repository.

Included in the repo:

- wiki
- people
- companies
- journal
- projects
- media
- raw clipped files
- templates
- workflows
- vault rules
- indexes and logs

MongoDB is intentionally deferred. Do not introduce MongoDB now.

Markdown + YAML frontmatter + Git is the correct starting point because it is:

- readable in Obsidian
- directly editable by agents
- versioned by Git
- portable
- easy to back up
- easy to refactor
- migratable to a database later if necessary

If a database is needed later, it should be introduced as an index/cache derived from Markdown, not as the primary source of truth.

## 5. Core information model

Memento has four major systems:

1. Wiki
2. People
3. Companies
4. Projects

Plus supporting systems:

- Journal
- Raw sources
- Media
- Templates
- Workflows
- Indexes
- Logs

The core distinction is:

- Wiki = knowledge
- People = relationships
- Companies = organizations, customers, employers, prospects, and business context
- Projects = action
- Journal = lived event stream
- Raw = source evidence
- Media = attachments and visual/audio evidence

## 6. Recommended vault structure

```text
Memento/
  AGENTS.md
  SCHEMA.md
  index.md
  log.md
  followups.md
  .gitignore

  raw/
    inbox/
      web-clips/
    processed/
      web-clips/
    assets/

  wiki/
    index.md
    sources/
    topics/
    concepts/
    entities/
    questions/
    comparisons/
    maps/

  people/
    index.md
    profiles/
    interactions/

  companies/
    index.md
    profiles/
    interactions/
    opportunities/

  projects/
    index.md
    active/
    incubating/
    paused/
    archived/
    templates/

  journal/
    index.md
    events/
      YYYY/
        MM/
    daily/
      YYYY/
        MM/
    weekly/
      YYYY/

  media/
    inbox/
    journal/
      YYYY/
        MM/
    people/
    companies/
    projects/
    sources/

  templates/
    journal-event.md
    person-profile.md
    company-profile.md
    interaction.md
    project.md
    source-summary.md

  workflows/
    journal-capture.md
    people-extraction.md
    company-extraction.md
    project-capture.md
    project-update.md
    raw-ingest.md
    daily-summary.md
    weekly-review.md
    git-safety.md
```

## 7. System files and what belongs where

### AGENTS.md

Purpose: agent behavior and permissions.

This file tells Argo and Lazarus how to behave inside the vault.

It should include:

- agent roles
- write permissions
- capture behavior
- when to ask follow-up questions
- git safety rules
- privacy rules
- conflict rules
- rules for journal, people, projects, wiki, and media
- rule that top-level folders are stable
- rule that agents must not invent facts

Use uppercase `AGENTS.md`, not only lowercase `agents.md`, because uppercase is the safer convention for automatic project-context loading in Hermes/agent workflows.

### SCHEMA.md

Purpose: data model and paths.

This file defines:

- top-level systems
- folder meanings
- note types
- required frontmatter
- naming conventions
- path conventions
- tag/domain taxonomy
- link conventions
- page thresholds
- status values for projects
- privacy levels

### templates/

Purpose: note shapes.

Templates define the default structure for new notes.

Examples:

- journal event
- person profile
- company profile
- interaction
- project
- source summary

### workflows/

Purpose: repeatable operating procedures.

Workflows define how Argo/Lazarus should perform common operations.

Examples:

- capture a journal event
- extract people from a journal event
- process direct people entry
- extract companies from journal, people, projects, and raw sources
- process direct company entry
- create/update project
- process raw Web Clipper file
- generate daily summary
- generate weekly review
- perform git sync safely

### index.md

Purpose: human and agent navigation.

The root `index.md` is the home page of Memento.

Each subsystem also has its own index:

- `wiki/index.md`
- `people/index.md`
- `companies/index.md`
- `projects/index.md`
- `journal/index.md`

### log.md

Purpose: append-only operational history.

Every significant agent write should append to `log.md`.

Examples:

- journal event created
- person profile updated
- project updated
- raw source processed
- daily summary generated
- weekly review generated
- lint completed

### followups.md

Purpose: central list of unresolved questions.

Follow-up questions should also remain in the relevant note, but `followups.md` gives Argo a global queue of missing context and open loops.

## 8. Wiki architecture

The wiki is for any emerging topic or synthesized knowledge.

Companies should not be hidden only in `wiki/entities/` when they are actionable as employers, customers, prospects, or CV/application targets. Those cases belong in `companies/`, with links back to any public/general `wiki/entities/` page when useful.

Topics should not be top-level folders. They should live inside `wiki/topics/` as topic pages or maps.

Examples of seed topic pages:

- `wiki/topics/career-strategy.md`
- `wiki/topics/software-engineering.md`
- `wiki/topics/test-automation.md`
- `wiki/topics/ai-assisted-development.md`
- `wiki/topics/entrepreneurship.md`
- `wiki/topics/marketing-and-sales.md`
- `wiki/topics/nutrition.md`
- `wiki/topics/relationships.md`
- `wiki/topics/personal-systems.md`

These are starting maps, not rigid folders.

Concept notes should emerge from collected information.

Examples:

- `wiki/concepts/distribution-risk-is-more-dangerous-than-build-risk.md`
- `wiki/concepts/test-automation-sells-when-framed-as-risk-reduction.md`
- `wiki/concepts/career-positioning-needs-proof-of-work.md`
- `wiki/concepts/nutrition-systems-work-when-adherence-is-easy.md`

The user defines intent and final meaning.

Argo and Lazarus propose emerging concepts and topic refinements based on evidence.

Stable taxonomy is jointly curated.

## 9. People architecture

People records are separate from the wiki.

Reason: private humans are not the same as general knowledge entities.

Public entities such as tools, public figures, institutions, and products belong in `wiki/entities/`.

Companies that are relevant as employers, customers, prospects, competitors, partners, or CV/application targets belong in `companies/`. If a company also needs general research notes, link the company profile to a public/general `wiki/entities/` page.

Private contacts belong in `people/`.

People can be updated in two ways:

1. Extracted from journal events
2. Direct entry from Telegram

Default input channel: Telegram.

Default input style: natural language.

Optional precision prefixes may be used:

- `journal:` for explicit journal event capture
- `person:` for explicit people/profile update
- `project:` for explicit project update or project idea

The system should still work without prefixes.

### People extraction from journal

When a journal event mentions a real person, Argo should decide whether the event contains durable relationship information.

If yes, Argo should create or update people records.

Argo should not create duplicate profiles when identity is ambiguous. It should search existing people first and ask a clarifying question when needed.

### Direct people entry

When the user directly provides information about a person, Argo should update `people/profiles/` without requiring that the information first pass through a journal event.

Example direct entries:

- "remember that Marco Rossi works at Finbank"
- "person: Jane likes Italian food and is preparing for QA interviews"
- "I should follow up with Sarah next week about the automation project"

Argo should preserve provenance by logging the update and, when useful, creating an interaction note or linking to the source journal event.

## 10. Companies architecture

Companies should be indexed separately from both people and the general wiki.

Reason: companies can be employers, customers, prospects, vendors, partners, competitors, or organizations mentioned in career/business contexts. They need CRM-like tracking similar to people, but with company-specific fields such as hiring status, customer fit, contacts, opportunities, CV/application history, and business relevance.

A public company can still have a general knowledge page in `wiki/entities/` when the note is about public facts or research. But when the company matters because the user may apply to it, sell to it, partner with it, or track contacts inside it, it should have a company profile under `companies/profiles/`.

Company profiles live in:

```text
companies/profiles/company-slug.md
```

Company interactions live in:

```text
companies/interactions/YYYY/MM/YYYY-MM-DD-HHMM-company-slug.md
```

Company opportunities live in:

```text
companies/opportunities/company-slug-opportunity.md
```

Companies can be updated in several ways:

1. Extracted from journal events
2. Extracted from people profiles and interactions
3. Extracted from project/customer discovery notes
4. Extracted from raw source material
5. Direct entry from Telegram

Default input channel: Telegram.

Optional prefix:

- `company:` for explicit company/profile/opportunity update

Example direct entries:

- "company: Finbank is hiring QA automation engineers and uses Playwright"
- "remember that Marco works at Finbank and their fintech team has flaky tests"
- "I sent my CV to Acme today for a QA automation role"
- "Acme could be a customer for the Playwright flake analyzer idea"

Company profiles should help answer:

- Should I send them a CV?
- Have I already applied or contacted them?
- Who do I know there?
- Could they be a customer?
- What pain signals have I heard from them?
- Which projects or offers might fit them?
- What follow-up is needed?

Argo should link companies to:

- people who work there
- journal events where they were mentioned
- interactions
- relevant projects
- opportunities
- wiki topics such as `career-strategy`, `test-automation`, `entrepreneurship`, and `marketing-and-sales`

Argo should ask a follow-up question when a company mention affects a CV/application, customer opportunity, sales lead, or open loop and key context is missing.

## 11. Relationship model and structured search

Memento should model relationships explicitly so Argo, Lazarus, Obsidian, and Dataview can answer structured questions across people, companies, projects, journal events, interactions, opportunities, and wiki topics.

Use two relationship layers:

1. Human-readable wikilinks in note bodies, such as `[[Marco Rossi]]`, `[[Finbank]]`, and `[[Project - Playwright Flake Analyzer]]`.
2. Machine-readable stable IDs in YAML frontmatter, such as `person_marco_rossi`, `company_finbank`, and `project_playwright_flake_analyzer`.

Wikilinks are for human navigation and Obsidian graph/backlinks.

Stable IDs are for structured search, Dataview queries, generated indexes, and agent reasoning.

### Stable ID convention

Recommended ID prefixes:

```text
person_<slug>
company_<slug>
project_<slug>
journal_<yyyy_mm_dd_hhmm_slug>
interaction_<yyyy_mm_dd_hhmm_slug>
opportunity_<company_slug>_<project_or_role_slug>
```

Display names may change, but IDs should remain stable once created.

### Core relations

Person relations:

```yaml
current_company: company_finbank
current_role: QA Lead
companies: [company_finbank]
projects: [project_playwright_flake_analyzer]
topics: [test-automation, career-strategy]
```

Company relations:

```yaml
contacts: [person_marco_rossi]
relevant_projects: [project_playwright_flake_analyzer]
opportunities: [opportunity_finbank_playwright_flake_analyzer]
pain_signals: [flaky Playwright tests]
topics: [test-automation, fintech]
```

Project relations:

```yaml
target_people: [person_marco_rossi]
target_companies: [company_finbank]
domains: [test-automation, entrepreneurship, marketing-and-sales]
```

Journal event relations:

```yaml
people: [person_marco_rossi]
companies: [company_finbank]
projects: [project_playwright_flake_analyzer]
topics: [test-automation]
```

Interaction relations:

```yaml
people: [person_marco_rossi]
companies: [company_finbank]
projects: [project_playwright_flake_analyzer]
source_event: journal_2026_05_15_qa_meetup
```

Opportunity relations:

```yaml
company: company_finbank
contacts: [person_marco_rossi]
project: project_playwright_flake_analyzer
status: identified
```

### Example relation flow

If the user texts:

```text
Met Marco Rossi at QA meetup. He works at Finbank as QA Lead. They have flaky Playwright tests and might want a demo.
```

Argo should create or update:

1. A journal event with the original capture.
2. `people/profiles/marco-rossi.md` with `current_company: company_finbank` and `current_role: QA Lead`.
3. `companies/profiles/finbank.md` with `contacts: [person_marco_rossi]` and a pain signal for flaky Playwright tests.
4. An interaction note linking the person, company, project, and source event.
5. A company opportunity if the project/customer signal is strong enough.
6. `people/index.md`, `companies/index.md`, `projects/index.md`, and `followups.md` if needed.

### Structured questions this should support

The relationship model should make it possible to answer questions like:

- Which people do I know at a specific company?
- Which companies have contacts related to test automation?
- Which companies did I already send my CV to?
- Which companies are possible customers for a QA automation product?
- Which prospects have Playwright or flaky-test pain signals?
- Which people are connected to projects in incubation?
- Which companies have open follow-ups?
- Which journal events mention both a person and a company?
- Which companies are connected to `career-strategy`, `test-automation`, or `marketing-and-sales`?

### Generated indexes, later

Do not add MongoDB now.

If structured querying becomes painful, Argo can later generate derived index files from Markdown frontmatter and wikilinks, for example:

```text
indexes/
  graph.json
  people-index.json
  companies-index.json
  projects-index.json
```

These files should be generated artifacts. The source of truth remains Markdown.

## 12. Journal architecture

The journal is not an evening diary.

The journal is an event stream.

The user will text events as they happen, primarily through Telegram.

Each meaningful Telegram journal capture should become one journal event note.

Journal event path:

```text
journal/events/YYYY/MM/YYYY-MM-DD-HHMM-short-title.md
```

Daily and weekly notes are generated summaries, not manual writing requirements.

Daily summary path:

```text
journal/daily/YYYY/MM/YYYY-MM-DD.md
```

Weekly review path:

```text
journal/weekly/YYYY/YYYY-Www.md
```

Each journal event should preserve the original text exactly.

The note should also contain a structured summary, extracted people, companies, projects, topics, media, and open loops.

### Follow-up behavior

Argo should not interrupt every journal capture.

Argo should ask immediate follow-up questions only when missing context affects:

- people profiles
- company profiles, CV/application records, or customer opportunities
- project records
- open loops
- commitments
- follow-up actions
- identity ambiguity
- important relationship context

Argo should ask at most 1-3 concise questions at once.

If the user does not answer, Argo should still save the event and record the missing context in the note and in `followups.md`.

## 13. Media architecture

Photos and other media shared through Telegram should be stored in a structured way inside the Memento vault.

Recommended path pattern:

```text
media/journal/YYYY/MM/YYYY-MM-DD-HHMM-short-title-01.jpg
media/people/person-slug/YYYY-MM-DD-description-01.jpg
media/companies/company-slug/YYYY-MM-DD-description-01.jpg
media/projects/project-slug/YYYY-MM-DD-description-01.jpg
media/sources/source-slug/filename.ext
```

Obsidian notes should link to media using wikilinks where possible.

Example:

```text
![[media/journal/2026/05/2026-05-15-1430-qa-meetup-01.jpg]]
```

Media is included in the private GitHub repository for now.

If the repository becomes too large, evaluate Git LFS or a split-media strategy later.

## 14. Projects architecture

Projects are separate from the wiki because they have state, decisions, execution, and outcomes.

A project can include:

- technical work
- business plan
- marketing
- customer discovery
- validation
- build plan
- launch plan
- revenue model
- kill criteria

Projects should be organized by status, not subject.

Recommended statuses:

- incubating
- active
- paused
- archived

Folder structure:

```text
projects/
  index.md
  incubating/
  active/
  paused/
  archived/
  templates/
```

Subjects/domains should be frontmatter and links, not folders.

Example:

```yaml
domains: [test-automation, entrepreneurship, marketing-and-sales]
status: incubating
stage: validation
```

Every project note should include:

- problem
- target user/customer
- value proposition
- technical plan
- marketing/distribution
- validation evidence
- business model if relevant
- next experiment
- kill criteria

This rule exists because the user is tired of unfinished and unprofitable projects.

No project should move from `incubating` to `active` without validation evidence or an explicit user override.

Validation evidence can include:

- user interviews
- real customer pain
- waitlist signups
- landing page tests
- paid pre-order
- client request
- repeated personal pain with clear target segment
- identified distribution channel

Not enough by itself:

- "I like the idea"
- "I can build it"
- "It would be cool"
- "AI can do it"
- "There is probably a market"

## 15. Raw source architecture

Obsidian Web Clipper saves raw files into the vault.

Recommended queue/archive structure:

```text
raw/
  inbox/
    web-clips/
  processed/
    web-clips/
  assets/
```

Argo processes only stable files from `raw/inbox/web-clips/`, ideally files older than 2-5 minutes.

After successful processing, Argo moves the raw source to `raw/processed/web-clips/`.

Raw processed files are immutable evidence.

Corrections belong in `wiki/`, not by editing processed raw sources.

A successful ingest should create or update:

- `wiki/sources/` source summary
- relevant `wiki/topics/`
- relevant `wiki/concepts/`
- relevant `wiki/entities/`
- `wiki/index.md`
- root `index.md` if needed
- `companies/index.md` if a company profile/opportunity is created or updated
- `log.md`

## 16. Input routing from Telegram

Telegram is the default capture interface for:

- journal events
- direct people updates
- direct company updates, CV/application tracking, and customer/prospect notes
- project ideas and project updates
- questions to Argo
- follow-up answers
- media capture

Default behavior is natural language.

Optional prefixes are supported for precision:

```text
journal: ...
person: ...
company: ...
project: ...
wiki: ...
```

Routing defaults:

- If the message describes something that happened, create a journal event.
- If it directly states durable information about a person, update people.
- If it directly states durable information about a company, employer, prospect, customer, CV target, or application, update companies.
- If it describes a build/business idea or project progress, update projects.
- If it asks a question, answer from Memento when relevant.
- If ambiguous, save minimally and ask one clarifying question.

## 17. Follow-up question policy

Argo should ask questions when missing information materially affects the usefulness of the record.

Ask immediately when missing info affects:

- person identity
- company identity, CV/application status, or customer/prospect status
- whether a person should be tracked
- whether a company should be tracked as employer, customer, prospect, partner, vendor, or competitor
- relationship context
- open loop or commitment
- project linkage
- project validation evidence
- next action
- media context

Do not ask immediately for every missing detail.

Do not ask for low-value perfection.

Do not block capture on missing context.

Always save the capture first, then ask.

If the user answers later, update the relevant note and clear the item from `followups.md`.

## 18. Git and synchronization model

GitHub private repo is the canonical synchronization layer.

Recommended working copies:

- Local macOS Obsidian clone: user-facing vault
- VPS `/opt/vault` or equivalent: Argo-operated clone

Argo should use a safe git workflow:

1. acquire lock
2. check git status
3. pull/rebase from origin
4. perform operation
5. update indexes/logs
6. commit changes
7. pull/rebase again if needed
8. push
9. release lock

Argo should not run overlapping write jobs against the vault.

Use a lock file or `flock` for scheduled jobs.

Lazarus should check git status before any manual write and avoid writing when Argo may be processing.

## 19. Privacy and safety principles

Memento is a private vault.

Sensitive areas:

- `people/`
- `companies/`
- `journal/`
- `media/people/`
- `media/companies/`
- `media/journal/`

Rules:

- Do not invent facts.
- Preserve original captures.
- Mark uncertain extractions as uncertain.
- Ask when identity is ambiguous.
- Do not create public-style entity pages for private contacts.
- Do not create generic wiki entity pages when the better record is a private company profile for a CV target, customer, prospect, or employer.
- Do not expose private notes externally without explicit user request.
- Keep GitHub repo private.
- Consider future separation/encryption only if sensitivity or repo size demands it.

## 20. Suggested note frontmatter

### Journal event

```yaml
---
type: journal-event
created: YYYY-MM-DDTHH:mm:ss
date: YYYY-MM-DD
time: HH:mm
source: telegram
event_type:
people: []
companies: []
projects: []
topics: []
media: []
location:
mood:
energy:
privacy: private
status: captured
needs_followup: false
followup_questions: []
---
```

### Person profile

```yaml
---
type: person
id:
name:
aliases: []
created:
updated:
relationship_type:
context:
location:
current_company:
current_role:
companies: []
projects: []
topics: []
contact:
  phone:
  email:
  telegram:
tags: [person]
privacy: private
last_interaction:
open_loops: 0
---
```

### Company profile

```yaml
---
type: company
id:
name:
aliases: []
created:
updated:
company_type: employer | customer | prospect | partner | vendor | competitor | other
status: research | interested | contacted | applied | interviewing | customer-discovery | active-customer | rejected | archived
website:
industry:
location:
size:
contacts: []
roles_of_interest: []
relevant_projects: []
pain_signals: []
cv_history: []
opportunities: []
tags: [company]
privacy: private
last_interaction:
open_loops: 0
---
```

### Interaction

```yaml
---
type: interaction
created:
date:
time:
people: []
companies: []
source_event:
projects: []
topics: []
media: []
followup_required: false
---
```

### Project

```yaml
---
type: project
status: incubating
stage: idea
domains: []
target_people: []
target_companies: []
created:
updated:
market_confidence: low
build_confidence: low
distribution_confidence: low
validation_evidence: []
privacy: private
---
```

## 21. Open assumptions still to confirm later

The user has already decided the major architecture. These points can be finalized during implementation:

1. Exact local macOS path for Memento.
2. Exact GitHub repo name for Memento.
3. Exact VPS clone path for Argo; previous plan used `/opt/vault`.
4. Whether media should use Git LFS immediately or only after repo size becomes a problem.
5. Final seed topic list; current proposal is acceptable as a starting set.
6. Exact Obsidian Web Clipper destination path.
7. Exact Telegram command/prefix vocabulary.
8. Whether daily summaries should run every night, every morning, or on demand.
9. Whether weekly reviews should run on Sunday, Monday, or on demand.

## 22. Design summary

Memento should be a private GitHub-backed Obsidian vault operated primarily by Argo and reviewed/planned by Lazarus.

The key separation is:

- `wiki/` for emerging knowledge and topics
- `people/` for private relationship memory
- `companies/` for employers, customers, prospects, applications, and business context
- `projects/` for technical/business/marketing execution
- `journal/` for event-stream capture
- `raw/` for source evidence
- `media/` for structured attachments
- `AGENTS.md`, `SCHEMA.md`, `templates/`, and `workflows/` for shared operating rules

The system should start simple with Markdown and Git, avoid MongoDB for now, preserve raw captures, ask follow-up questions only when they matter, index both people and companies as actionable relationship/business records, and force projects to include validation/business/marketing thinking so they do not become unfinished unprofitable builds.
