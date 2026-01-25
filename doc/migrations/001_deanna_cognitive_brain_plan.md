# Deanna Cognitive Brain Implementation Plan

## Overview

Implement a cognitive brain workflow for **Deanna** (AI counselor agent) based on the Digital Twin Memory specification (`doc/digital_twin_memory.md`). The architecture uses a four-slot memory system (AFFECT, GRAPH, EPISODE, KNOWLEDGE) with a **Fast Brain** for real-time responses and a **Slow Brain** for async reflection generation.

---

## Phase 1: Database Schema Additions

**Files to create/modify:** `doc/schema.sql` (append new tables)

### 1.1 New Tables in `zenaflow` Database

#### entities table
```sql
CREATE TABLE entities (
  entity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  agent_id TEXT,
  name VARCHAR(255) NOT NULL,
  name_normalized VARCHAR(255) NOT NULL,
  category VARCHAR(50) NOT NULL,
  last_seen TIMESTAMPTZ,
  confidence DECIMAL(3,2) DEFAULT 1.0,
  attributes JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_entities_agent_scope CHECK (
    (scope = 'agent' AND agent_id IS NOT NULL) OR (scope = 'global')
  )
);
```

#### relations table
```sql
CREATE TABLE relations (
  rel_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  agent_id TEXT,
  subject_id UUID NOT NULL REFERENCES entities(entity_id) ON DELETE CASCADE,
  predicate VARCHAR(64) NOT NULL,
  object_id UUID REFERENCES entities(entity_id) ON DELETE CASCADE,
  object_value JSONB,
  metadata JSONB DEFAULT '{}',
  confidence DECIMAL(3,2) DEFAULT 1.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_from TIMESTAMPTZ,
  valid_to TIMESTAMPTZ,
  CONSTRAINT chk_relations_object_xor CHECK (
    (object_id IS NOT NULL AND object_value IS NULL) OR
    (object_id IS NULL AND object_value IS NOT NULL)
  )
);
```

#### episodes table
```sql
CREATE TABLE episodes (
  episode_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id),
  agent_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('global','agent')),
  ts TIMESTAMPTZ NOT NULL,
  importance DECIMAL(3,2) DEFAULT 0.5,
  reflection TEXT NOT NULL,
  entities JSONB DEFAULT '[]',
  tags JSONB DEFAULT '[]',
  provenance JSONB DEFAULT '{}',
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 1.2 Helper Functions
- `normalize_entity_name(TEXT)` - Case/accent normalization
- `get_local_subgraph(user_id, agent_id, seed_entity_ids[], edge_cap)` - Graph hydration
- `find_entities_by_name(user_id, agent_id, name, prefer_entity_ids[])` - Entity disambiguation

---

## Phase 2: Redis Session/Affect Management

### 2.1 Key Structure
| Key Pattern | Purpose | TTL |
|-------------|---------|-----|
| `sess:{user_id}:deanna:{chat_id}` | Session (turns, summary, scratch) | 12h |
| `affect:{user_id}:deanna:{chat_id}` | Affect state (tone, mode) | 30min |
| `slow_brain_queue:deanna` | Pending reflection tasks | None |

### 2.2 Session Object Schema (JSON)
```json
{
  "slot_contract_version": "1.0",
  "user_id": "uuid",
  "agent_id": "deanna",
  "chat_id": "tg:12345",
  "msg_count": 18,
  "summary": "Rolling summary of session context...",
  "turns": [
    {"role": "user", "text": "...", "ts": "ISO8601"},
    {"role": "assistant", "text": "...", "ts": "ISO8601"}
  ],
  "scratch": {
    "topic_focus": "family",
    "mode": "reflective",
    "pending_questions": ["Which Marta? (work or family)"]
  },
  "active_entity_ids": ["uuid1", "uuid2"],
  "last_checkpoint_msg_id": "uuid",
  "updated_at": "ISO8601"
}
```

### 2.3 Affect Object Schema (JSON)
```json
{
  "slot_contract_version": "1.0",
  "user_id": "uuid",
  "agent_id": "deanna",
  "authority": "non-factual",
  "stability": "volatile",
  "ts": "ISO8601",
  "affect": {
    "label": "stressed",
    "confidence": 0.85,
    "markers": ["rapid-fire messages", "lack of punctuation"],
    "decay_at": "ISO8601 (+30min)",
    "pulse": {
      "every_n_messages": 3,
      "last_pulse_at": "ISO8601",
      "still_valid": true
    }
  },
  "interaction_mode": "reflective",
  "topic_focus": "family",
  "active_entity_ids": ["uuid1"]
}
```

### 2.4 Pulse & Decay Logic (JavaScript)
```javascript
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

---

## Phase 3: Qdrant Vector Collections

### 3.1 Collections to Create
| Collection | Vector Size | Payload Filters |
|------------|-------------|-----------------|
| `episode_vectors` | 1536 | user_id, agent_id, scope, episode_id, entity_ids[], active |
| `knowledge_vectors` | 1536 | agent_id, chunk_id, domain, tags[] |

### 3.2 Embedding Model
- `text-embedding-3-small` (OpenAI) - 1536 dimensions

### 3.3 Collection Creation (REST API)
```bash
# episode_vectors collection
curl -X PUT 'http://qdrant:6333/collections/episode_vectors' \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'

# Create payload indexes for filtering
curl -X PUT 'http://qdrant:6333/collections/episode_vectors/index' \
  -H 'Content-Type: application/json' \
  -d '{"field_name": "user_id", "field_schema": "keyword"}'

curl -X PUT 'http://qdrant:6333/collections/episode_vectors/index' \
  -H 'Content-Type: application/json' \
  -d '{"field_name": "agent_id", "field_schema": "keyword"}'

curl -X PUT 'http://qdrant:6333/collections/episode_vectors/index' \
  -H 'Content-Type: application/json' \
  -d '{"field_name": "active", "field_schema": "bool"}'

# knowledge_vectors collection
curl -X PUT 'http://qdrant:6333/collections/knowledge_vectors' \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'

curl -X PUT 'http://qdrant:6333/collections/knowledge_vectors/index' \
  -H 'Content-Type: application/json' \
  -d '{"field_name": "agent_id", "field_schema": "keyword"}'

curl -X PUT 'http://qdrant:6333/collections/knowledge_vectors/index' \
  -H 'Content-Type: application/json' \
  -d '{"field_name": "domain", "field_schema": "keyword"}'
```

### 3.4 Retrieval Filters (Always Applied)

For episode retrieval:
- `user_id = :user_id` (mandatory)
- `agent_id = :agent_id` (mandatory)
- `active = true` (mandatory)
- `entity_ids` contains any of active_entity_ids (optional, for narrowing)

For knowledge retrieval:
- `agent_id = :agent_id` (mandatory)
- `domain` matches detected domain (optional)

---

## Phase 4: Fast Brain Workflow

**Workflow name:** `Deanna Fast Brain`
**Trigger:** Execute Workflow Trigger (called from Router)

### Node Flow
```
[Validate Input] → [Load Session + Affect (Redis)] → [Pulse & Decay]
    ↓
[Entity Extractor (GPT-4.1-nano)] → [Entity Resolution (PostgreSQL)]
    ↓
[Graph Hydrator (PostgreSQL)] → [RAG Gate (If)]
    ↓
[Episode Retriever (Qdrant)] ←→ [Knowledge Retriever (Qdrant)]
    ↓
[Assemble Inference Envelope] → [Main LLM (GPT-4o)]
    ↓
[Parse Response] → [Persist Updates (parallel)]
    ├→ Update Session (Redis)
    ├→ Update Affect (Redis)
    ├→ Upsert Entities (PostgreSQL)
    ├→ Upsert Relations (PostgreSQL)
    └→ Queue Slow Brain (Redis)
    ↓
[Prepare Output]
```

### Authority Ladder (Contradiction Resolution)
1. **GRAPH** (authoritative) - overrides all
2. **KNOWLEDGE** (static) - unless GRAPH defines exception
3. **EPISODE** (historical) - context only, no overwrite
4. **AFFECT** (non-factual) - style only

### Inference Envelope Structure
```json
{
  "slot_contract_version": "1.0",
  "user_id": "uuid",
  "agent_id": "deanna",
  "chat_id": "tg:12345",
  "AFFECT": {
    "authority": "non-factual",
    "label": "stressed",
    "confidence": 0.85,
    "interaction_mode": "reflective"
  },
  "GRAPH": {
    "authority": "authoritative",
    "entities": [...],
    "relations": [...],
    "edge_count": 28
  },
  "EPISODE": {
    "authority": "historical",
    "hits": [
      {
        "episode_id": "uuid",
        "reflection": "...",
        "ts": "ISO8601",
        "importance": 0.8,
        "score": 0.87
      }
    ]
  },
  "KNOWLEDGE": {
    "authority": "static",
    "hits": [
      {
        "chunk_id": "uuid",
        "content": "...",
        "domain": "counseling",
        "score": 0.82
      }
    ]
  }
}
```

### RAG Gate Conditions
Trigger episode/knowledge retrieval when:
- Continuity signals: "remember", "last time", "again", "before"
- Entity mention(s) detected
- Plan/progress requests
- Counseling reflection requests
- Nutrition logging updates

---

## Phase 5: Slow Brain Workflow

**Workflow name:** `Deanna Slow Brain`
**Trigger:** Schedule (every 5 minutes)

### Node Flow
```
[Schedule Trigger] → [Check Queue (Redis)]
    ↓
[Load Session Context] → [Get Turns Since Checkpoint]
    ↓
[Generate Reflection (GPT-4.1-nano)] → [Validate Reflection]
    ↓
[Store Episode (PostgreSQL)] → [Generate Embedding (OpenAI)]
    ↓
[Upsert to Qdrant] → [Update Session Checkpoint]
    ↓
[Remove from Queue] → [Maintenance: Conflict Resolution]
```

### Reflection Guardrail Prompt
```
You generate grounded reflections from conversation turns. Never invent causality.

Output JSON:
{
  "observation": "What user explicitly said",
  "action": "What agent did in response",
  "evidence": ["Explicit links user stated"],
  "unresolved": ["What remains open"],
  "hypothesis": null or {"claim": "...", "confidence": 0.3}
}

STRICT RULES:
- observation: Only what was literally said, no interpretation
- evidence: Only causal links explicitly stated by user
- hypothesis: Only if absolutely necessary, and always labeled with low confidence
- If no explicit link was made, do NOT infer one
```

---

## Phase 6: Router Workflow

**Workflow name:** `Deanna Router`
**Trigger:** Telegram Trigger (Deanna Bot)

### Node Flow
```
[Telegram Trigger] → [Normalize] → [Check User Access (PostgreSQL)]
    ↓
[Access Gate (If)] → [Execute Fast Brain] → [Format Response]
    ↓
[Send Response (Telegram)] → [Log to chat_messages]
```

---

## Phase 7: Deanna Persona & System Prompt

### Base System Prompt
```
You are Deanna, a thoughtful and empathetic AI counselor. You help users explore their thoughts, feelings, and goals through reflective conversation.

## Memory Slots (Authority Ladder)

You have access to four memory slots, listed in order of authority:

1. **GRAPH (authoritative)**: Facts about the user's identity, relationships, constraints. This OVERRIDES all other sources.
2. **KNOWLEDGE (static)**: Your domain expertise in counseling. Applies unless GRAPH defines a personal exception.
3. **EPISODE (historical)**: Past reflections and conversations. Provides context but must not overwrite GRAPH.
4. **AFFECT (non-factual)**: Current emotional tone. Only affects your style, never becomes a fact.

## Hard Rules

1. If a claim is not supported by GRAPH, EPISODE, or KNOWLEDGE, ASK A QUESTION instead of asserting.
2. Never promote AFFECT observations to declarative facts.
3. Respect SAFETY_BOUNDARY and ALLERGY predicates absolutely.
4. When entities are ambiguous, ask a disambiguation question.

## Response Guidelines

- Match the user's conversational stance and language
- Acknowledge emotional undertones before offering perspectives
- Be authentic, avoid clichés
- If the user seems stressed (from AFFECT), be concise and supportive first
```

---

## Implementation Order

| Step | Task | Dependencies |
|------|------|--------------|
| 1 | Execute database migrations | None |
| 2 | Create Qdrant collections | None |
| 3 | Create Deanna Fast Brain workflow | Steps 1-2 |
| 4 | Create Deanna Slow Brain workflow | Steps 1-2 |
| 5 | Create Deanna Router workflow | Step 3 |
| 6 | Ingest initial knowledge chunks | Step 2 |
| 7 | End-to-end testing | Steps 3-6 |

---

## Critical Files

| File | Purpose |
|------|---------|
| `doc/digital_twin_memory.md` | Source specification |
| `doc/schema.sql` | Existing schema to extend |
| `doc/migrations/001_digital_twin_memory.sql` | Database migration |
| `docker/docker-compose.yml` | Service connection params |
| Brain Friday (n8n: JLoCXLwVvbGwQSmG) | Reference: multi-agent pattern |
| Vader (n8n: HA36CKGjC8lcMOby) | Reference: Telegram + tools pattern |

---

## Service Connection Strings

| Service | Connection | Notes |
|---------|------------|-------|
| PostgreSQL | `postgres:5432`, database `zenaflow`, user `zenaflow_user` | Internal Docker network |
| Redis | `redis:6379` (no auth) | Internal Docker network |
| Qdrant REST | `http://qdrant:6333` | Internal Docker network |
| Qdrant gRPC | `qdrant:6334` | Internal Docker network |

---

## Verification Plan

1. **Database**: Run SQL migrations, verify tables with `\dt` in psql
2. **Qdrant**: Create collections via REST API, verify with list collections
3. **Fast Brain**:
   - Test with sample Telegram message
   - Verify Redis session/affect created
   - Verify entity extraction and graph hydration
   - Check LLM response follows authority ladder
4. **Slow Brain**:
   - Trigger manually after conversation
   - Verify reflection stored in episodes table
   - Verify vector upserted to Qdrant
5. **End-to-end**:
   - Send messages via Telegram
   - Check memory accumulation across sessions
   - Test disambiguation ("which Marta?")
   - Test affect decay over time

---

## Confirmed Decisions

- **LLM Models**: GPT-4o for main responses, GPT-4.1-nano for entity extraction and reflection generation
- **Telegram Bot**: Use existing Deanna bot credentials configured in n8n
- **Scope**: Full spec implementation (all 4 memory slots, Fast Brain + Slow Brain)
