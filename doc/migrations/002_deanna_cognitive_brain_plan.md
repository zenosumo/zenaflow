# Deanna Cognitive Brain Implementation Plan

**Version:** 1.0
**Created:** 2026-01-31
**Status:** In Progress
**Specification:** [doc/digital_twin_memory.md](../digital_twin_memory.md)

---

## Executive Summary

Implement a cognitive brain workflow for **Deanna** (AI counselor agent) based on the Digital Twin Memory specification. The architecture uses a **four-slot memory system** (AFFECT, GRAPH, EPISODE, KNOWLEDGE) with a **Fast Brain** for real-time responses and a **Slow Brain** for async reflection generation.

### Confirmed Decisions
- **LLM Models**: GPT-4o for main responses, GPT-4.1-nano for entity extraction and reflection generation
- **Telegram Bot**: Use existing Deanna bot credentials configured in n8n
- **Scope**: Full spec implementation (all 4 memory slots, Fast Brain + Slow Brain)

---

## Part 1: Completed Infrastructure

### ✅ 1.1 Database Schema (PostgreSQL)

**Migration file:** `doc/migrations/001_digital_twin_memory.sql`
**Executed:** 2026-01-31

#### New Tables Created

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `entities` | Identity nodes (Person, Location, Goal, Food, etc.) | entity_id, user_id, scope, agent_id, name, name_normalized, category, confidence, attributes |
| `relations` | Graph edges + literal facts | rel_id, subject_id, predicate, object_id/object_value, confidence, valid_from/to |
| `episodes` | Episodic reflections (NOT raw chat) | episode_id, user_id, agent_id, reflection, entities[], tags[], importance, active |

#### Helper Functions Created

| Function | Purpose | Signature |
|----------|---------|-----------|
| `normalize_entity_name()` | Case/accent normalization for entity matching | `(input TEXT) → TEXT` |
| `get_local_subgraph()` | Graph hydration with priority-based edge selection | `(user_id, agent_id, seed_entity_ids[], edge_cap) → TABLE` |
| `find_entities_by_name()` | Entity disambiguation (prefers active_entity_ids, then recency) | `(user_id, agent_id, name, prefer_entity_ids[]) → TABLE` |

#### Indexes Created
- `idx_entities_user_scope_cat` - User/scope/category queries
- `idx_entities_user_name_norm` - Name lookups
- `idx_entities_user_agent` - Agent-scoped entity queries
- `idx_relations_user_subject/object` - Graph traversal
- `idx_relations_predicate` - Predicate filtering
- `idx_episodes_user_agent_ts` - Episode retrieval by time
- `idx_episodes_entities_gin` - Entity-based episode filtering

---

### ✅ 1.2 Vector Store (Qdrant)

**Qdrant Endpoint:** `qdrant:6333` (Docker internal DNS on `core_net`)

#### Collections Created

| Collection | Vector Size | Distance | Purpose |
|------------|-------------|----------|---------|
| `episode_vectors` | 1536 | Cosine | Semantic search over episodic reflections |
| `knowledge_vectors` | 1536 | Cosine | Domain expertise RAG for Deanna |

#### Payload Indexes

**episode_vectors:**
- `user_id` (keyword) - mandatory filter
- `agent_id` (keyword) - mandatory filter
- `scope` (keyword) - global/agent separation
- `active` (bool) - soft-delete filtering

**knowledge_vectors:**
- `agent_id` (keyword) - agent-scoped knowledge
- `domain` (keyword) - domain categorization
- `chunk_id` (keyword) - unique chunk identifier

---

## Part 2: n8n Workflows to Build

### 2.1 Overview

Three workflows need to be created in n8n:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Deanna Router** | Telegram Trigger | Entry point, auth, routing to Fast Brain |
| **Deanna Fast Brain** | Execute Workflow | Real-time response with memory slots |
| **Deanna Slow Brain** | Schedule (5 min) | Async reflection generation |

---

### 2.2 Deanna Router Workflow

**Purpose:** Entry point for Telegram messages, handles authentication and routing.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEANNA ROUTER                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Telegram Trigger] ─→ [Normalize Payload] ─→ [Resolve + Authorize] │
│                                                (resolve_user_app_*)   │
│                                                       │               │
│                                                       ▼               │
│                                              [Access Gate (If)]       │
│                                            Authorized│Not Authorized  │
│                                                       │               │
│                                                       ▼               │
│                        [Insert Pending chat_messages (dedupe)] [Send Deny]  │
│                                          │                            │
│                                          ▼                            │
│                               [Execute Fast Brain]                    │
│                                          │                            │
│                                          ▼                            │
│                                   [Format Response]                   │
│                                          │                            │
│                                          ▼                            │
│                              [Send Telegram Response]                 │
│                                          │                            │
│                                          ▼                            │
│                               [Complete chat_messages]                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Node Details

| Node | Type | Configuration |
|------|------|---------------|
| Telegram Trigger | n8n-nodes-base.telegramTrigger | Credential: Deanna Bot, Updates: message |
| Normalize Payload | n8n-nodes-base.code | Extract telegram_user_id, telegram_id, chat_id, text, platform info |
| Resolve + Authorize User | n8n-nodes-base.postgres | Call `resolve_user_app_access('deanna', telegram_user_id, telegram_id)` |
| Access Gate | n8n-nodes-base.if | Continue only when decision is `authorized` (fail-closed) |
| Insert Pending chat_messages | n8n-nodes-base.postgres | Insert pending row with dedupe by `(platform, message_id)` |
| Execute Fast Brain | n8n-nodes-base.executeWorkflow | Call Deanna Fast Brain workflow |
| Format Response | n8n-nodes-base.set | Prepare response for Telegram |
| Send Telegram Response | n8n-nodes-base.telegram | Send response to user |
| Complete chat_messages | n8n-nodes-base.postgres | Update pending row to `completed` with response text |
| Send Deny | n8n-nodes-base.telegram | Reject blocked/suspended/unauthorized users with clear message |

#### Normalize Payload Code
```javascript
const msg = $input.first().json.message;

return {
  normalized: {
    user_id: null, // Will be resolved from DB
    telegram_id: msg.from.username ? `@${msg.from.username}` : null,
    telegram_user_id: msg.from.id,
    chat_id: `tg:${msg.chat.id}`,
    message_id: msg.message_id,
    text: msg.text || '',
    platform: 'telegram',
    agent_id: 'deanna',
    ts: new Date().toISOString()
  },
  raw: msg
};
```

#### Resolve + Authorize User (PostgreSQL)
```sql
SELECT *
FROM resolve_user_app_access(
  'deanna'::text,
  $1::bigint,      -- telegram_user_id (preferred)
  $2::text         -- telegram_id with @ prefix (fallback)
);
```

**Router contract:**
- Input params: `normalized.telegram_user_id`, `normalized.telegram_id`
- Output fields: `user_id`, `user_app_id`, `app_id`, `decision`, `user_status`, `active_after`
- Allowed continuation: `decision = 'authorized'`
- Deny decisions: `unknown_user`, `blocked`, `suspended`, `app_inactive`, `no_app_access`

#### Insert Pending `chat_messages` (PostgreSQL)
```sql
INSERT INTO chat_messages (
  user_app_id,
  request_text,
  source_payload,
  status
) VALUES (
  $1::uuid,        -- authorized user_app_id
  $2::text,        -- request text
  $3::jsonb,       -- normalized platform payload
  'pending'
)
ON CONFLICT ((source_payload->>'platform'), (source_payload->>'message_id'))
DO NOTHING
RETURNING message_id;
```

**Idempotency rule:** if no row is returned, treat as duplicate webhook delivery and stop the workflow before Fast Brain.

#### Complete `chat_messages` (PostgreSQL)
```sql
UPDATE chat_messages
SET
  response_text = $2::text,
  status = 'completed',
  responded_at = NOW()
WHERE message_id = $1::uuid;
```

---

### 2.3 Deanna Fast Brain Workflow

**Purpose:** Real-time response generation with all four memory slots.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           DEANNA FAST BRAIN                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  [Execute Workflow Trigger]                                                   │
│           │                                                                   │
│           ▼                                                                   │
│  [Validate Input Contract]                                                    │
│           │                                                                   │
│           ▼                                                                   │
│  ┌────────┴────────┐                                                         │
│  │  PARALLEL LOAD  │                                                         │
│  ├─────────────────┤                                                         │
│  │ [Load Session]  │  [Load Affect]                                          │
│  │    (Redis)      │    (Redis)                                              │
│  └────────┬────────┘                                                         │
│           │                                                                   │
│           ▼                                                                   │
│  [Merge Session + Affect]                                                     │
│           │                                                                   │
│           ▼                                                                   │
│  [Pulse & Decay] ──────────────────────────────────────────────────────────┐ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Entity Extractor] (GPT-4.1-nano)                                         │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Entity Resolution] (PostgreSQL)                                           │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Graph Hydrator] (PostgreSQL: get_local_subgraph)                          │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Compute Retrieval Flags] ───────────────┬───────────────────────────────┐  │ │
│         (Code Node)                        │                               │  │ │
│           │                                │                               │  │ │
│           ▼                                ▼                               ▼  │ │
│   [If Episodes]                     [If Knowledge]                [Set Defaults]│ │
│   true → Episode Retriever          true → Knowledge Retriever    episode_results=[]│
│   false → skip                      false → skip                  knowledge_results=[]│
│           │                                │                               │  │ │
│           └────────────────────────────────┴───────────────────────────────┘  │ │
│                          │                                                   │ │
│                          ▼                                                   │ │
│  [Assemble Inference Envelope]                                              │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Main LLM Call] (GPT-4o + Deanna Persona)                                  │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Parse LLM Response]                                                        │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  ┌────────┴────────────────────────────────────────────┐                    │ │
│  │              PARALLEL PERSIST                        │                    │ │
│  ├──────────────────────────────────────────────────────┤                    │ │
│  │ [Update Session] [Update Affect] [Upsert Entities]  │                    │ │
│  │    (Redis)          (Redis)       (PostgreSQL)      │                    │ │
│  │                                                      │                    │ │
│  │ [Upsert Relations] [Queue Slow Brain]               │                    │ │
│  │   (PostgreSQL)        (Redis LPUSH)                 │                    │ │
│  └──────────────────────────────────────────────────────┘                    │ │
│           │                                                                 │ │
│           ▼                                                                 │ │
│  [Prepare Output]                                                            │ │
│                                                                              │ │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### Key Node Configurations

##### Load Session (Redis)
```
Key: sess:{{ $json.normalized.user_id }}:deanna:{{ $json.normalized.chat_id }}
Operation: Get
```

##### Load Affect (Redis)
```
Key: affect:{{ $json.normalized.user_id }}:deanna:{{ $json.normalized.chat_id }}
Operation: Get
```

##### Pulse & Decay (Code Node)
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

##### Entity Extractor (OpenAI Chat Model)
```
Model: gpt-4.1-nano
System Prompt:
Extract entities mentioned in the user message. Return JSON:
{
  "entities": [
    {"name": "Marta", "category": "Person", "confidence": 0.9},
    {"name": "gym", "category": "Location", "confidence": 0.8}
  ],
  "topic_signals": ["family", "health"]
}

Categories: Person, Location, Goal, Food, Habit, Event, Organization, Pet, Medication, Activity, Emotion, Preference, Other
```

##### Entity Resolution (PostgreSQL)
```sql
SELECT * FROM find_entities_by_name(
  $1::uuid,           -- user_id
  'deanna',           -- agent_id
  $2::text,           -- entity name
  $3::uuid[]          -- active_entity_ids from session
);
```

##### Graph Hydrator (PostgreSQL)
```sql
SELECT * FROM get_local_subgraph(
  $1::uuid,           -- user_id
  'deanna',           -- agent_id
  $2::uuid[],         -- seed_entity_ids (resolved + active)
  40                  -- edge_cap
);
```

##### Compute Retrieval Flags (Code Node)
```javascript
for (const item of items) {
  const text = (item.json.normalized?.text || "").toLowerCase();
  const hasEntityMention = (item.json.resolved_entities?.length || 0) > 0;
  const hasContinuitySignal = /\b(remember|last time|again|before|we talked)\b/i.test(text);
  const hasReflectionRequest = /\b(how am i|progress|feeling|reflect)\b/i.test(text);

  item.json.should_retrieve_episodes =
    hasEntityMention || hasContinuitySignal || hasReflectionRequest;

  item.json.should_retrieve_knowledge =
    hasReflectionRequest || /\b(help|advice|suggest)\b/i.test(text);
}

return items;
```

##### If Episodes (If Node)
```
Condition: {{ $json.should_retrieve_episodes }} is true
True branch: Episode Retriever
False branch: pass-through
```

##### If Knowledge (If Node)
```
Condition: {{ $json.should_retrieve_knowledge }} is true
True branch: Knowledge Retriever
False branch: pass-through
```

##### Set Defaults for No Retrieval (Set Node)
```
Always ensure downstream contract:
  - episode_results = [] when episodes branch is skipped
  - knowledge_results = [] when knowledge branch is skipped
```

##### Episode Retriever (Qdrant Vector Store)
```
Collection: episode_vectors
Embedding Model: text-embedding-3-small
Top K: 5
Filters:
  - user_id = {{ $json.normalized.user_id }}
  - agent_id = "deanna"
  - active = true
```

##### Knowledge Retriever (Qdrant Vector Store)
```
Collection: knowledge_vectors
Embedding Model: text-embedding-3-small
Top K: 3
Filters:
  - agent_id = "deanna"
```

##### Assemble Inference Envelope (Code Node)
```javascript
const envelope = {
  slot_contract_version: "1.0",
  user_id: $json.normalized.user_id,
  agent_id: "deanna",
  chat_id: $json.normalized.chat_id,

  AFFECT: {
    authority: "non-factual",
    label: $json.redis_affect?.affect?.label || "neutral",
    confidence: $json.redis_affect?.affect?.confidence || 0,
    interaction_mode: $json.redis_affect?.interaction_mode || "default"
  },

  GRAPH: {
    authority: "authoritative",
    entities: $json.resolved_entities || [],
    relations: $json.graph_relations || [],
    edge_count: ($json.graph_relations || []).length
  },

  EPISODE: {
    authority: "historical",
    hits: ($json.episode_results || []).map(e => ({
      episode_id: e.metadata.episode_id,
      reflection: e.pageContent,
      ts: e.metadata.ts,
      importance: e.metadata.importance,
      score: e.score
    }))
  },

  KNOWLEDGE: {
    authority: "static",
    hits: ($json.knowledge_results || []).map(k => ({
      chunk_id: k.metadata.chunk_id,
      content: k.pageContent,
      domain: k.metadata.domain,
      score: k.score
    }))
  }
};

return { envelope };
```

##### Main LLM Call (OpenAI Chat Model)
```
Model: gpt-4o
System Prompt: [See Deanna Persona below]
User Prompt: {{ $json.normalized.text }}
Context: {{ JSON.stringify($json.envelope) }}
```

##### Update Session (Redis)
```
Key: sess:{{ $json.normalized.user_id }}:deanna:{{ $json.normalized.chat_id }}
Operation: Set
Value: [Updated session JSON with new turn, incremented msg_count]
TTL: 43200 (12 hours)
```

##### Update Affect (Redis)
```
Key: affect:{{ $json.normalized.user_id }}:deanna:{{ $json.normalized.chat_id }}
Operation: Set
Value: [Updated affect from LLM output]
TTL: 1800 (30 minutes)
```

##### Queue Slow Brain (Redis)
```
Key: slow_brain_queue:deanna
Operation: LPUSH
Value: {
  task_id,
  user_id,
  chat_id,
  checkpoint_msg_id,
  queued_at,
  retry_count: 0
}
Condition: msg_count % 10 == 0 OR memory_write_needed flag
```

---

### 2.4 Deanna Slow Brain Workflow

**Purpose:** Async reflection generation and episodic memory creation.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           DEANNA SLOW BRAIN                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  [Schedule Trigger] ──→ [Acquire Run Lock] ──→ [Lock Acquired?] ──→ [Stop]   │
│     (Every 5 min)           (SET NX EX)               No                      │
│                              │                                                │
│                              │ Yes                                             │
│                              ▼                                                │
│                    [Claim Task] (RPOPLPUSH queue → processing)                │
│                              │                                                │
│                              ▼                                                │
│                    [Task Claimed?] ──→ [Release Lock + Stop]                  │
│                         No                                                     │
│                              │ Yes                                             │
│                              ▼                                                │
│                    [Idempotency Guard] (SET NX done:task_id)                  │
│                              │                                                │
│                              ├─ Already Done ─→ [ACK Task] ─→ [Claim Next]    │
│                              │                                                │
│                              ▼                                                │
│                    [Load Session Context] (Redis)                             │
│                              │                                                │
│                              ▼                                                │
│                    [Get Turns Since Checkpoint]                               │
│                              │                                                │
│                              ▼                                                │
│                    [Enough Turns?] ──→ [Skip + ACK] ──→ [Claim Next]         │
│                        (< 3 turns)                                            │
│                              │                                                │
│                              │ Yes (≥ 3 turns)                                │
│                              ▼                                                │
│                    [Generate Reflection] (GPT-4.1-nano)                       │
│                              │                                                │
│                              ▼                                                │
│                    [Validate Reflection Structure]                            │
│                              │                                                │
│                              ▼                                                │
│                    [Store Episode] (PostgreSQL INSERT)                        │
│                              │                                                │
│                              ▼                                                │
│                    [Generate Embedding] (OpenAI)                              │
│                              │                                                │
│                              ▼                                                │
│                    [Upsert to Qdrant]                                         │
│                              │                                                │
│                              ▼                                                │
│                    [Update Session Checkpoint] (Redis)                        │
│                              │                                                │
│                              ├─ Success ──────────→ [ACK Task] ─→ [Claim Next]│
│                              │                                                │
│                              └─ Failure ─→ [Retry/DLQ + ACK] ─→ [Claim Next]  │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### Key Node Configurations

##### Schedule Trigger
```
Interval: Every 5 minutes
```

##### Acquire Run Lock (Redis)
```
Key: slow_brain_lock:deanna
Operation: SET
Value: {{ $execution.id }}
Mode: NX
TTL: 300 seconds
```

##### Claim Task (Redis)
```
Operation: RPOPLPUSH
Source: slow_brain_queue:deanna
Destination: slow_brain_processing:deanna
If null: no task available for this run
```

##### Idempotency Guard (Redis)
```
Key: slow_brain_done:deanna:{{ $json.task_id }}
Operation: SET
Value: 1
Mode: NX
TTL: 604800 seconds (7 days)
If SET fails: task already processed, ACK and continue
```

##### ACK Task (Redis)
```
Operation: LREM
Key: slow_brain_processing:deanna
Count: 1
Value: {{ $json.raw_claimed_task }}
```

##### Retry/DLQ on Failure (Redis)
```
If retry_count < 5:
  - Increment retry_count
  - LPUSH slow_brain_queue:deanna <updated_task_payload>
  - ACK original from processing list

If retry_count >= 5:
  - LPUSH slow_brain_dlq:deanna <task_payload_with_error>
  - ACK original from processing list
```

##### Release Run Lock (Redis)
```
Operation: DEL
Key: slow_brain_lock:deanna
Note: lock TTL also protects against worker crash
```

##### Generate Reflection (OpenAI)
```
Model: gpt-4.1-nano
System Prompt:
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

##### Store Episode (PostgreSQL)
```sql
INSERT INTO episodes (
  user_id, agent_id, scope, ts, importance,
  reflection, entities, tags, provenance, active
) VALUES (
  $1, 'deanna', 'agent', NOW(), $2,
  $3, $4::jsonb, $5::jsonb, $6::jsonb, TRUE
) RETURNING episode_id;
```

##### Upsert to Qdrant (HTTP Request)
```
Method: PUT
URL: http://qdrant:6333/collections/episode_vectors/points
Body: {
  "points": [{
    "id": "{{ $json.episode_id }}",
    "vector": {{ $json.embedding }},
    "payload": {
      "user_id": "{{ $json.user_id }}",
      "agent_id": "deanna",
      "scope": "agent",
      "episode_id": "{{ $json.episode_id }}",
      "entity_ids": {{ $json.entity_ids }},
      "importance": {{ $json.importance }},
      "ts": "{{ $json.ts }}",
      "active": true
    }
  }]
}
```

---

### 2.5 Deanna Persona System Prompt

```markdown
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

## Memory Write Plan

When you identify new facts or updates, include a memory_write_plan in your response:

```json
{
  "entities": [{"name": "...", "category": "...", "action": "create|update"}],
  "relations": [{"subject": "...", "predicate": "...", "object": "...", "action": "create|update"}],
  "needs_reflection": true|false
}
```
```

---

## Part 3: Service Connections

| Service | Internal Address | External Access | Credentials |
|---------|-----------------|-----------------|-------------|
| PostgreSQL | `postgres:5432` | SSH tunnel `localhost:5432` | User: `zenaflow_user`, DB: `zenaflow` |
| Redis | `redis:6379` | SSH tunnel | No auth |
| Qdrant | `qdrant:6333` | SSH tunnel `localhost:6333` | No auth |
| n8n | `127.0.0.1:5678` | `workflow.zenaflow.com` | Via UI |
| OpenAI | External API | N/A | API Key in n8n credentials |

---

## Part 4: Implementation Checklist

### Phase 1: Infrastructure ✅
- [x] Execute database migrations (entities, relations, episodes tables)
- [x] Create helper functions (normalize_entity_name, get_local_subgraph, find_entities_by_name)
- [x] Create Qdrant collection: episode_vectors
- [x] Create Qdrant collection: knowledge_vectors
- [x] Create payload indexes for both collections
- [ ] Execute migration `doc/migrations/002_digital_twin_memory.sql` (access-control hardening)

### Phase 2: n8n Workflows (Pending)
- [ ] Create Deanna Router workflow
  - [ ] Telegram Trigger with Deanna Bot credentials
  - [ ] Normalize Payload node
  - [ ] Resolve + Authorize User (PostgreSQL function call)
  - [ ] Access Gate with fail-closed decision checks
  - [ ] Insert pending chat_messages row with dedupe handling
  - [ ] Execute Fast Brain call
  - [ ] Send Telegram Response
  - [ ] Complete chat_messages row (status=completed, responded_at)
  - [ ] Send deny response for non-authorized decisions

- [ ] Create Deanna Fast Brain workflow
  - [ ] Execute Workflow Trigger
  - [ ] Validate Input Contract
  - [ ] Load Session (Redis)
  - [ ] Load Affect (Redis)
  - [ ] Pulse & Decay (Code)
  - [ ] Entity Extractor (GPT-4.1-nano)
  - [ ] Entity Resolution (PostgreSQL)
  - [ ] Graph Hydrator (PostgreSQL)
  - [ ] Compute Retrieval Flags (Code)
  - [ ] If Episodes (If)
  - [ ] If Knowledge (If)
  - [ ] Set retrieval defaults for skipped branches
  - [ ] Episode Retriever (Qdrant)
  - [ ] Knowledge Retriever (Qdrant)
  - [ ] Assemble Inference Envelope
  - [ ] Main LLM Call (GPT-4o)
  - [ ] Parse LLM Response
  - [ ] Update Session (Redis)
  - [ ] Update Affect (Redis)
  - [ ] Upsert Entities (PostgreSQL)
  - [ ] Upsert Relations (PostgreSQL)
  - [ ] Queue Slow Brain (Redis)
  - [ ] Prepare Output

- [ ] Create Deanna Slow Brain workflow
  - [ ] Schedule Trigger (5 minutes)
  - [ ] Acquire run lock (Redis SET NX EX)
  - [ ] Claim task atomically (Redis RPOPLPUSH queue → processing)
  - [ ] Idempotency guard (SET NX done:task_id)
  - [ ] Load Session Context
  - [ ] Get Turns Since Checkpoint
  - [ ] Generate Reflection (GPT-4.1-nano)
  - [ ] Validate Reflection
  - [ ] Store Episode (PostgreSQL)
  - [ ] Generate Embedding (OpenAI)
  - [ ] Upsert to Qdrant
  - [ ] Update Session Checkpoint
  - [ ] ACK task from processing list (Redis LREM)
  - [ ] Retry or DLQ failed tasks
  - [ ] Release run lock

### Phase 3: Testing (Pending)
- [ ] Verify Telegram trigger receives messages
- [ ] Test user authorization flow
- [ ] Test Redis session creation/update
- [ ] Test affect decay logic
- [ ] Test entity extraction and resolution
- [ ] Test graph hydration
- [ ] Test episode retrieval from Qdrant
- [ ] Test knowledge retrieval from Qdrant
- [ ] Test main LLM response with memory context
- [ ] Test slow brain reflection generation
- [ ] Test episode vector storage
- [ ] End-to-end conversation test
- [ ] Test disambiguation ("which Marta?")
- [ ] Test affect decay over time
- [ ] Test slow-brain queue idempotency (duplicate deliveries)
- [ ] Test slow-brain retry/DLQ behavior on failures

---

## Part 5: File References

| File | Purpose |
|------|---------|
| [doc/digital_twin_memory.md](../digital_twin_memory.md) | Source specification |
| [doc/schema.sql](../schema.sql) | Existing core schema |
| [doc/migrations/001_digital_twin_memory.sql](./001_digital_twin_memory.sql) | Memory schema migration |
| [doc/migrations/002_digital_twin_memory.sql](./002_digital_twin_memory.sql) | Access-control hardening migration |
| [doc/migrations/001_deanna_cognitive_brain_plan.md](./001_deanna_cognitive_brain_plan.md) | Initial plan (archived) |
| [docker/docker-compose.yml](../../docker/docker-compose.yml) | Service configuration |

---

## Part 6: Next Steps

1. **Create n8n workflows** using the n8n MCP or manually in the UI
2. **Configure credentials** for OpenAI, Telegram (Deanna Bot), PostgreSQL, Redis
3. **Test each workflow** independently before connecting
4. **Run end-to-end tests** with real Telegram messages
5. **Ingest initial knowledge chunks** for Deanna's counseling domain
6. **Monitor and tune** edge caps, TTLs, and retrieval thresholds
