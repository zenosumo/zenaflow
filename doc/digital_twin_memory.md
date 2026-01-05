# Digital Twin Core — Memory Implementation Spec (v1.0)

This document describes the **memory architecture** for a multi-agent system (e.g., **Anaketa** and **Deanna**) running on a shared VPS + Docker + **n8n**, primarily accessed via a Telegram bot.

Core goal: **Common Infrastructure, Specialized Intelligence** — shared deterministic memory backbone + agent-specific behavior, without latency blowups or “creative drift”.

---

## 0) Glossary

- **User**: a human identity (Telegram user).
- **Agent**: a persona + policy bundle + memory rules (e.g., Anaketa, Deanna).
- **Session**: short-lived state for a `(user, agent, chat)` tuple.
- **Scope**:
  - `global`: shared across all agents for the same user.
  - `agent`: visible only to one agent for the same user.

---

## 1) Slot Contract (Unified Prompt Slots)

Every agent workflow must provide the same four slots to the final **Inference Node**.

| Slot | Source | Stability | Authority | Role |
|---|---|---:|---|---|
| `{{AFFECT}}` | Redis | volatile | non-factual | Tone/filter only |
| `{{GRAPH}}` | Postgres (SQL) | persistent | authoritative | Identity & constraints |
| `{{EPISODE}}` | Postgres + Vector Index | historical | historical | Continuity (“journal reflections”) |
| `{{KNOWLEDGE}}` | Chunk store + Vector Index | static | static | Domain expertise |

### Authority Ladder (Contradiction Resolution)

1. **GRAPH (authoritative)** overrides all.
2. **KNOWLEDGE (static)** applies unless GRAPH defines a personal exception.
3. **EPISODE (historical)** provides context; must not overwrite GRAPH.
4. **AFFECT (non-factual)** only affects style; must not become a “trait” or fact.

**Hard rule:** if a claim is not supported by GRAPH/EPISODE/KNOWLEDGE, **ask a question** instead of asserting.

---

## 2) Memory Types (by Access Pattern)

### 2.1 Working Memory (Redis) — “Now”
**Pattern:** read/write every message, TTL-based.

**Stores:**
- session summary + last N turns (trimmed)
- scratch variables (mode flags, pending questions)
- active entity ids
- message count
- affect state (separately typed)

**Keying:**
- `sess:{user_id}:{agent_id}:{chat_id}`  (session object)
- `affect:{user_id}:{agent_id}:{chat_id}` (affect object)

**Recommended storage:** 1 JSON blob per key (simple, 1 round-trip). Hash/List is acceptable but increases calls.

---

### 2.2 Declarative Memory (Postgres) — “Truth-ish User Model”
**Pattern:** read often, update occasionally, must be deterministic and auditable.

**Stores:**
- entities (people, places, goals, foods, habits…)
- relations (graph edges) and literal facts (`obj_value`)
- confidence + timestamps for drift handling
- global vs agent scope separation

---

### 2.3 Episodic Memory (Postgres + Vector Index) — “Then”
**Pattern:** append occasionally; retrieve via similarity + filters.

**Stores:**
- **Reflections** (not raw chat)
- pointers to source message range for provenance
- metadata: entity_ids, topic tags, importance, timestamps

**Vector DB role:** index for semantic retrieval; **not canonical storage**.

---

### 2.4 Knowledge Memory (Chunk Store + Vector Index) — “Library”
**Pattern:** agent-scoped, relatively static, retrieved by intent/tool-need detection.

**Stores:**
- pre-digested chunks from docs (.md ingestion is allowed, but runtime store is chunks)
- optionally web-digested knowledge chunks
- tagged by agent and domain

---

## 3) Redis Data Contracts

### 3.1 Session Object (example)
```json
{
  "slot_contract_version": "1.0",
  "user_id": 123,
  "agent_id": "deanna",
  "chat_id": "tg:987",
  "msg_count": 18,
  "summary": "Short rolling summary of the session...",
  "turns": [
    {"role": "user", "text": "…"},
    {"role": "assistant", "text": "…"}
  ],
  "scratch": {
    "topic_focus": "family",
    "mode": "reflective",
    "pending_questions": ["Which Marta? (work or family)"]
  },
  "active_entity_ids": ["8f4ccf3b-0d86-4c07-a6f6-2f0ea2f7c6a1"],
  "updated_at": "2026-01-03T01:02:10Z"
}
```

### 3.2 AFFECT Slot (Redis JSON)
**Intent:** ephemeral interaction filter (tone/mode), **non-factual**.

```json
{
  "slot_contract_version": "1.0",
  "user_id": 123,
  "agent_id": "deanna",
  "authority": "non-factual",
  "stability": "volatile",
  "ts": "2026-01-03T01:01:50Z",
  "affect": {
    "label": "stressed",
    "confidence": 0.85,
    "markers": ["rapid-fire messages", "lack of punctuation"],
    "decay_at": "2026-01-03T01:31:50Z",
    "pulse": {
      "every_n_messages": 3,
      "last_pulse_at": "2026-01-03T01:01:50Z",
      "still_valid": true
    }
  },
  "interaction_mode": "reflective",
  "topic_focus": "family",
  "active_entity_ids": ["8f4ccf3b-0d86-4c07-a6f6-2f0ea2f7c6a1"]
}
```

**Rules:**
- TTL ~30 minutes (or use `decay_at` + pulse logic).
- Never persist affect as declarative fact unless explicitly stated by user and intentionally promoted.

---

## 4) Postgres Schema (Graph + Episodic)

### 4.1 Entities (Identity Nodes)
```sql
CREATE TABLE entities (
  entity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INT NOT NULL REFERENCES users(id),
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  agent_id TEXT, -- required when scope='agent'
  name VARCHAR(255) NOT NULL,
  name_normalized VARCHAR(255) NOT NULL,
  category VARCHAR(50) NOT NULL, -- 'Person', 'Location', 'Goal', 'Food', ...
  last_seen TIMESTAMP,
  confidence DECIMAL(3,2) DEFAULT 1.0,
  attributes JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_entities_user_scope_cat ON entities(user_id, scope, category);
CREATE INDEX idx_entities_user_name_norm ON entities(user_id, name_normalized);
```

**Normalization:** `name_normalized = lower(unaccent(name))` to handle `marta` vs `Marta` and diacritics.

**Multiple same-name entities:** store different `entity_id`s; disambiguate via context + attributes + aliases.

---

### 4.2 Relations (Graph Edges + Literal Facts)
```sql
CREATE TABLE relations (
  rel_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INT NOT NULL REFERENCES users(id),
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  agent_id TEXT, -- required when scope='agent'
  subject_id UUID NOT NULL REFERENCES entities(entity_id),
  predicate VARCHAR(64) NOT NULL,
  object_id UUID REFERENCES entities(entity_id),
  object_value JSONB, -- literal fact when object isn't an entity
  metadata JSONB DEFAULT '{}',
  confidence DECIMAL(3,2) DEFAULT 1.0,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now(),
  valid_from TIMESTAMP,
  valid_to TIMESTAMP,
  CHECK (
    (object_id IS NOT NULL AND object_value IS NULL)
    OR (object_id IS NULL AND object_value IS NOT NULL)
  )
);

CREATE UNIQUE INDEX uniq_relations
  ON relations(user_id, scope, COALESCE(agent_id,''), subject_id, predicate,
              COALESCE(object_id, '00000000-0000-0000-0000-000000000000'::uuid),
              COALESCE(object_value, '{}'::jsonb));

CREATE INDEX idx_rel_subject ON relations(user_id, subject_id);
CREATE INDEX idx_rel_object ON relations(user_id, object_id);
CREATE INDEX idx_rel_predicate ON relations(predicate);
```

**Scope merge rule (retrieval):**
- Retrieve `scope='global'` + `(scope='agent' AND agent_id=:agent_id)`.
- Conflicts resolve by predicate class:
  - identity predicates: global wins
  - agent-domain predicates (diet plans, counseling modes): agent wins

---

### 4.3 Episodic Reflections (Canonical Store)
```sql
CREATE TABLE episodes (
  episode_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INT NOT NULL REFERENCES users(id),
  agent_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  ts TIMESTAMP NOT NULL,
  importance DECIMAL(3,2) DEFAULT 0.5,
  reflection TEXT NOT NULL,
  entities JSONB DEFAULT '[]',     -- array of entity_ids
  tags JSONB DEFAULT '[]',
  provenance JSONB DEFAULT '{}',   -- message ids / range
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_episodes_user_agent_ts ON episodes(user_id, agent_id, ts DESC);
```

---

## 5) Vector Index Placement (Qdrant or pgvector)

Vector DB is an **index layer**, not memory truth.

### Recommended collections
- `episode_vectors` (user_id + agent_id scoped)
- `knowledge_vectors` (agent-scoped)
- optional: `semantic_fact_vectors` (user_id scoped) if needed

### Required payload fields (filters)
- `user_id`
- `agent_id`
- `scope`
- `episode_id` or `chunk_id`
- `entity_ids[]` (for fast narrowing)

### Retrieval filters (must always include)
- `user_id = :user_id`
- `agent_id = :agent_id` (or knowledge collection agent filter)
- scope rules

This prevents cross-user “Marta bleed”.

---

## 6) Retrieval Policy (JIT Context)

### 6.1 Entity-Triggered Loading (Direct SQL)
- If user mentions “Mom” (or alias), fetch `entities` by normalized name + aliases for that user.
- If pronoun/ellipsis, use Redis `active_entity_ids` + `topic_focus`.

### 6.2 RAG Gate (when to hit vectors)
Trigger episode/knowledge retrieval when:
- continuity signals: “remember”, “last time”, “again”
- entity mention(s)
- plan/progress requests
- counseling reflection requests
- nutrition logging updates

### 6.3 Similarity Retrieval (episodes)
Avoid a hard `> 0.8` threshold. Use top-K + relative cutoff:
- fetch top 5–8
- keep those passing `score > max(0.65, top1 - 0.12)`
- also filter by `entity_ids` if present

### 6.4 Graph Hydration (Local Subgraph)
Use seed entities (mentioned + recent) → 1-hop relations → prioritize and edge-cap.

**Priority order:**
1) agent scoped edges (for this agent)
2) critical predicates (ALLERGY, SAFETY_BOUNDARY, MEDICATION, INTOLERANCE)
3) confidence
4) updated_at / last_seen

**Edge cap:** 30–60 (tune for TTFT).

---

## 7) n8n Nodes (Core Flow)

### 7.1 Fast Brain (Main Flow)
1. Telegram Trigger
2. Identify user + agent + chat
3. Load Redis session + affect
4. **Pulse & Decay** (affect maintenance)
5. Graph Hydrator (SQL → local subgraph)
6. Episode retrieval (optional, gated) via vector index
7. Knowledge retrieval (optional, gated) via vector index
8. Assemble Inference Envelope + validate schema
9. Single LLM call (response + memory-write plan)
10. Persist:
    - session update (Redis)
    - declarative upserts (Postgres)
    - (optional) queue slow-brain tasks

### 7.2 Slow Brain (Async Flow)
Trigger:
- inactivity timer (e.g., 5–10 minutes) OR
- memory_write_needed flag OR
- batch size threshold

Steps:
1. collect last N turns since last checkpoint
2. create reflection (cheap model)
3. store episode row (Postgres)
4. embed reflection + upsert to vector index
5. maintenance: deactivate conflicting/outdated low-confidence facts if needed

---

## 8) Pulse & Decay Node (n8n Function JS)

Drop-in hardened example:

```js
const item = items[0];
const now = new Date();

const redisAffect = item.json.redis_affect ?? null;
const session = item.json.session ?? {};
const lastMsg = (item.json.last_message ?? "").toString();

if (!redisAffect?.affect) {
  item.json.redis_affect = {
    slot_contract_version: "1.0",
    authority: "non-factual",
    stability: "volatile",
    affect: {
      label: "neutral",
      confidence: 0,
      markers: [],
      decay_at: new Date(now.getTime() + 30*60*1000).toISOString()
    },
    interaction_mode: "default",
    ts: now.toISOString()
  };
  return items;
}

const affect = redisAffect;

// Rule 1: Temporal Decay
if (new Date(affect.affect.decay_at) < now) {
  affect.affect.label = "neutral";
  affect.affect.confidence = 0.0;
  affect.affect.markers = ["expired_decay"];
}

// Rule 2: Pulse decay every N messages
const msgCount = Number(session.msg_count ?? 0);
const pulseEvery = Number(affect.affect?.pulse?.every_n_messages ?? 3);

if (msgCount > 0 && msgCount % pulseEvery === 0) {
  const shortFunctional = lastMsg.trim().length < 10;
  if (shortFunctional) affect.affect.confidence *= 0.7;

  // gentle decay prevents loops
  affect.affect.confidence *= 0.95;

  affect.affect.pulse = {
    every_n_messages: pulseEvery,
    last_pulse_at: now.toISOString(),
    still_valid: affect.affect.confidence >= 0.3
  };
}

// Rule 3: Forced Flush
if (affect.affect.confidence < 0.3) {
  affect.affect.label = "neutral";
  affect.affect.confidence = 0.0;
  affect.affect.markers = [...(affect.affect.markers ?? []), "forced_flush_low_conf"];
}

item.json.redis_affect = affect;
return items;
```

**Policy:** pulse node only decays/flushes; boosts require explicit markers (e.g., “I’m furious”).

---

## 9) Forgetting (Intentional Amnesia)

Forgetting must be a first-class operation with **scope + tombstones**.

### 9.1 Soft delete (default)
- add `active=false` or `deleted_at` on entities/relations/episodes
- store `forget_reason` + `forgotten_at`

Vector retrieval must filter `active=true`.

### 9.2 Hard delete (only if required)
- delete Postgres rows
- delete vectors in Qdrant by `episode_id` / `chunk_id`
- clear related Redis keys or remove entity ids from `active_entity_ids`

### 9.3 Scope of forgetting
- session: remove Redis session + affect, optionally today’s episodes
- agent: remove agent-scoped facts/episodes
- global: remove global facts across all agents

---

## 10) Disambiguation (Marta vs marta; two Martas)

### 10.1 Case-insensitive lookup
- `name_normalized` + alias normalization: `lower(unaccent(text))`

### 10.2 Multiple identical names
Resolve to an **entity_id**:
1) query all matching `name_normalized='marta'` for this user
2) if >1:
   - prefer Redis `active_entity_ids`
   - else prefer most recent `last_seen`
   - else ask one disambiguation question (“work Marta or family Marta?”)
3) store an alias (e.g., “work Marta”) into `attributes.aliases[]`

---

## 11) Reflection Engine Prompt Guardrail (Slow Brain)

Reflections must be grounded. No invented causality.

**Template:**
- Observation: what user explicitly said
- Action: what agent did
- Evidence: explicit link(s) user stated
- Unresolved: what remains open
- Hypothesis (optional, low confidence): only if labeled as hypothesis

**Strict rule:** if no explicit link was made, do not infer one.

---

## 12) Operational Notes

- Use schema versioning: `slot_contract_version` increments only with migrations.
- Prefer “local subgraph hydration” + caps to avoid token firehoses.
- Keep the “brain” (LLM) on a strict typed diet: validated JSON slots + authority ladder.

---

## Appendix A — Inference Envelope (Recommended)

Wrap all slots in a single object before the LLM call:

```json
{
  "slot_contract_version": "1.0",
  "user_id": 123,
  "agent_id": "deanna",
  "chat_id": "tg:987",
  "AFFECT": { "...": "typed affect slot" },
  "GRAPH": { "...": "typed graph payload" },
  "EPISODE": { "hits": [ /* reflection summaries */ ] },
  "KNOWLEDGE": { "hits": [ /* domain chunks */ ] }
}
```

Validate this envelope in n8n before inference to prevent schema drift.
