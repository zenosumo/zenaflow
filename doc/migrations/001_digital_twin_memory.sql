-- ============================================================================
-- DIGITAL TWIN MEMORY SCHEMA MIGRATION v1.0
-- ============================================================================
-- Purpose: Memory system for multi-agent digital twin architecture
-- Implements: AFFECT (Redis), GRAPH (PostgreSQL), EPISODE (PostgreSQL+Qdrant), KNOWLEDGE (Qdrant)
-- Specification: doc/digital_twin_memory.md
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ============================================================================
-- ENTITIES TABLE (Identity Nodes)
-- ============================================================================
-- Stores entities mentioned in conversations: people, locations, goals, foods, etc.
-- Scoping:
--   - global: shared across all agents for the same user
--   - agent: visible only to one agent for the same user
-- ============================================================================

CREATE TABLE entities (
    entity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    scope TEXT NOT NULL,
    agent_id TEXT,
    name VARCHAR(255) NOT NULL,
    name_normalized VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL,
    last_seen TIMESTAMPTZ,
    confidence DECIMAL(3,2) DEFAULT 1.0,
    attributes JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_entities_user_id
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    CONSTRAINT chk_entities_scope_valid
        CHECK (scope IN ('global', 'agent')),

    CONSTRAINT chk_entities_agent_scope
        CHECK (
            (scope = 'agent' AND agent_id IS NOT NULL) OR
            (scope = 'global')
        ),

    CONSTRAINT chk_entities_confidence_range
        CHECK (confidence >= 0.0 AND confidence <= 1.0),

    CONSTRAINT chk_entities_category_valid
        CHECK (category IN (
            'Person', 'Location', 'Goal', 'Food', 'Habit', 'Event',
            'Organization', 'Pet', 'Medication', 'Activity', 'Emotion',
            'Preference', 'Belief', 'Skill', 'Health', 'Other'
        ))
);

-- Indexes for entity queries
CREATE INDEX idx_entities_user_scope_cat ON entities(user_id, scope, category);
CREATE INDEX idx_entities_user_name_norm ON entities(user_id, name_normalized);
CREATE INDEX idx_entities_user_agent ON entities(user_id, agent_id) WHERE agent_id IS NOT NULL;
CREATE INDEX idx_entities_user_last_seen ON entities(user_id, last_seen DESC) WHERE last_seen IS NOT NULL;
CREATE INDEX idx_entities_attributes_gin ON entities USING GIN (attributes);

-- Apply updated_at trigger
CREATE TRIGGER trg_entities_set_updated_at_before_update
    BEFORE UPDATE ON entities
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION trg_set_updated_at();

COMMENT ON TABLE entities IS 'Identity nodes for user knowledge graph (GRAPH memory slot)';
COMMENT ON COLUMN entities.name_normalized IS 'Lowercase, unaccented name for case-insensitive matching';
COMMENT ON COLUMN entities.scope IS 'global = shared across agents, agent = agent-specific';
COMMENT ON COLUMN entities.attributes IS 'Flexible JSONB for aliases, metadata. Example: {"aliases": ["Mom", "Mother"], "birthday": "1965-03-15"}';

-- ============================================================================
-- RELATIONS TABLE (Graph Edges + Literal Facts)
-- ============================================================================
-- Stores relationships between entities (graph edges) and literal facts
-- Either object_id (entity reference) OR object_value (literal) must be set
-- Supports temporal validity (valid_from, valid_to) for time-bound facts
-- ============================================================================

CREATE TABLE relations (
    rel_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    scope TEXT NOT NULL,
    agent_id TEXT,
    subject_id UUID NOT NULL,
    predicate VARCHAR(64) NOT NULL,
    object_id UUID,
    object_value JSONB,
    metadata JSONB DEFAULT '{}',
    confidence DECIMAL(3,2) DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_from TIMESTAMPTZ,
    valid_to TIMESTAMPTZ,

    CONSTRAINT fk_relations_user_id
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    CONSTRAINT fk_relations_subject_id
        FOREIGN KEY (subject_id) REFERENCES entities(entity_id) ON DELETE CASCADE,

    CONSTRAINT fk_relations_object_id
        FOREIGN KEY (object_id) REFERENCES entities(entity_id) ON DELETE CASCADE,

    CONSTRAINT chk_relations_scope_valid
        CHECK (scope IN ('global', 'agent')),

    CONSTRAINT chk_relations_agent_scope
        CHECK (
            (scope = 'agent' AND agent_id IS NOT NULL) OR
            (scope = 'global')
        ),

    CONSTRAINT chk_relations_object_xor
        CHECK (
            (object_id IS NOT NULL AND object_value IS NULL) OR
            (object_id IS NULL AND object_value IS NOT NULL)
        ),

    CONSTRAINT chk_relations_confidence_range
        CHECK (confidence >= 0.0 AND confidence <= 1.0),

    CONSTRAINT chk_relations_validity_period
        CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_from <= valid_to)
);

-- Unique constraint to prevent duplicate relations
CREATE UNIQUE INDEX uniq_relations
    ON relations(
        user_id,
        scope,
        COALESCE(agent_id, ''),
        subject_id,
        predicate,
        COALESCE(object_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(object_value, '{}'::jsonb)
    );

-- Indexes for relation queries
CREATE INDEX idx_relations_user_subject ON relations(user_id, subject_id);
CREATE INDEX idx_relations_user_object ON relations(user_id, object_id) WHERE object_id IS NOT NULL;
CREATE INDEX idx_relations_predicate ON relations(predicate);
CREATE INDEX idx_relations_user_scope_agent ON relations(user_id, scope, agent_id);
CREATE INDEX idx_relations_valid_period ON relations(valid_from, valid_to) WHERE valid_to IS NOT NULL;
CREATE INDEX idx_relations_metadata_gin ON relations USING GIN (metadata);

-- Apply updated_at trigger
CREATE TRIGGER trg_relations_set_updated_at_before_update
    BEFORE UPDATE ON relations
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION trg_set_updated_at();

COMMENT ON TABLE relations IS 'Graph edges and literal facts for user knowledge graph (GRAPH memory slot)';
COMMENT ON COLUMN relations.predicate IS 'Relation type: HAS_CHILD, LIVES_IN, ALLERGY, PREFERS, GOAL, MEDICATION, etc.';
COMMENT ON COLUMN relations.object_value IS 'Literal value when target is not an entity. Example: {"value": "vegetarian", "since": "2024-01"}';
COMMENT ON COLUMN relations.valid_from IS 'Start of validity period (NULL = always valid from creation)';
COMMENT ON COLUMN relations.valid_to IS 'End of validity period (NULL = still valid)';

-- ============================================================================
-- EPISODES TABLE (Episodic Reflections)
-- ============================================================================
-- Stores reflections (NOT raw chat) from conversations
-- Vector embeddings stored in Qdrant, canonical data here
-- Supports soft-delete via active flag for forgetting
-- ============================================================================

CREATE TABLE episodes (
    episode_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    agent_id TEXT NOT NULL,
    scope TEXT NOT NULL,
    ts TIMESTAMPTZ NOT NULL,
    importance DECIMAL(3,2) DEFAULT 0.5,
    reflection TEXT NOT NULL,
    entities JSONB DEFAULT '[]',
    tags JSONB DEFAULT '[]',
    provenance JSONB DEFAULT '{}',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_episodes_user_id
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    CONSTRAINT chk_episodes_scope_valid
        CHECK (scope IN ('global', 'agent')),

    CONSTRAINT chk_episodes_importance_range
        CHECK (importance >= 0.0 AND importance <= 1.0)
);

-- Indexes for episode queries
CREATE INDEX idx_episodes_user_agent_ts ON episodes(user_id, agent_id, ts DESC);
CREATE INDEX idx_episodes_user_active ON episodes(user_id, active) WHERE active = TRUE;
CREATE INDEX idx_episodes_entities_gin ON episodes USING GIN (entities);
CREATE INDEX idx_episodes_tags_gin ON episodes USING GIN (tags);
CREATE INDEX idx_episodes_importance ON episodes(user_id, importance DESC) WHERE active = TRUE;

COMMENT ON TABLE episodes IS 'Episodic reflections for conversation continuity (EPISODE memory slot)';
COMMENT ON COLUMN episodes.reflection IS 'Structured reflection text (observation, action, evidence, unresolved)';
COMMENT ON COLUMN episodes.entities IS 'Array of entity_ids mentioned in this episode';
COMMENT ON COLUMN episodes.tags IS 'Semantic tags for retrieval. Example: ["family", "planning", "emotional"]';
COMMENT ON COLUMN episodes.provenance IS 'Source message references. Example: {"message_ids": ["uuid1", "uuid2"], "chat_id": "tg:123"}';
COMMENT ON COLUMN episodes.active IS 'FALSE = soft-deleted (forgotten), excluded from retrieval';

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Normalize entity names for case-insensitive, accent-insensitive matching
CREATE OR REPLACE FUNCTION normalize_entity_name(input TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN lower(unaccent(trim(input)));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION normalize_entity_name IS 'Normalize text for entity matching: lowercase + remove accents + trim';

-- Get local subgraph for seed entities (1-hop relations)
-- Priority order: agent-scoped > critical predicates > confidence > recency
CREATE OR REPLACE FUNCTION get_local_subgraph(
    p_user_id UUID,
    p_agent_id TEXT,
    p_seed_entity_ids UUID[],
    p_edge_cap INT DEFAULT 40
)
RETURNS TABLE (
    subject_id UUID,
    subject_name VARCHAR,
    subject_category VARCHAR,
    predicate VARCHAR,
    object_id UUID,
    object_name VARCHAR,
    object_category VARCHAR,
    object_value JSONB,
    confidence DECIMAL,
    scope TEXT,
    priority_rank INT
) AS $$
BEGIN
    RETURN QUERY
    WITH prioritized_relations AS (
        SELECT
            r.subject_id,
            e_subj.name as subj_name,
            e_subj.category as subj_category,
            r.predicate,
            r.object_id,
            e_obj.name as obj_name,
            e_obj.category as obj_category,
            r.object_value,
            r.confidence,
            r.scope,
            CASE
                -- Agent-scoped edges for this agent have highest priority
                WHEN r.scope = 'agent' AND r.agent_id = p_agent_id THEN 1
                -- Critical safety predicates
                WHEN r.predicate IN ('ALLERGY', 'SAFETY_BOUNDARY', 'MEDICATION', 'INTOLERANCE', 'EMERGENCY_CONTACT') THEN 2
                -- High-confidence global facts
                WHEN r.scope = 'global' AND r.confidence >= 0.8 THEN 3
                -- Everything else
                ELSE 4
            END as priority_rank
        FROM relations r
        LEFT JOIN entities e_obj ON r.object_id = e_obj.entity_id
        LEFT JOIN entities e_subj ON r.subject_id = e_subj.entity_id
        WHERE r.user_id = p_user_id
          AND (r.subject_id = ANY(p_seed_entity_ids) OR r.object_id = ANY(p_seed_entity_ids))
          AND (r.scope = 'global' OR (r.scope = 'agent' AND r.agent_id = p_agent_id))
          AND (r.valid_to IS NULL OR r.valid_to > NOW())
        ORDER BY priority_rank, r.confidence DESC, r.updated_at DESC
        LIMIT p_edge_cap
    )
    SELECT
        pr.subject_id,
        pr.subj_name,
        pr.subj_category,
        pr.predicate,
        pr.object_id,
        pr.obj_name,
        pr.obj_category,
        pr.object_value,
        pr.confidence,
        pr.scope,
        pr.priority_rank
    FROM prioritized_relations pr;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_local_subgraph IS 'Hydrate local subgraph from seed entities with priority-based edge selection';

-- Find entities by normalized name with disambiguation support
CREATE OR REPLACE FUNCTION find_entities_by_name(
    p_user_id UUID,
    p_agent_id TEXT,
    p_name TEXT,
    p_prefer_entity_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    entity_id UUID,
    name VARCHAR,
    category VARCHAR,
    confidence DECIMAL,
    last_seen TIMESTAMPTZ,
    is_preferred BOOLEAN,
    scope TEXT
) AS $$
DECLARE
    v_normalized_name TEXT;
BEGIN
    v_normalized_name := normalize_entity_name(p_name);

    RETURN QUERY
    SELECT
        e.entity_id,
        e.name,
        e.category,
        e.confidence,
        e.last_seen,
        CASE WHEN p_prefer_entity_ids IS NOT NULL AND e.entity_id = ANY(p_prefer_entity_ids) THEN TRUE ELSE FALSE END as is_preferred,
        e.scope
    FROM entities e
    WHERE e.user_id = p_user_id
      AND e.name_normalized = v_normalized_name
      AND (e.scope = 'global' OR (e.scope = 'agent' AND e.agent_id = p_agent_id))
    ORDER BY
        -- Preferred entities first (from active_entity_ids)
        CASE WHEN p_prefer_entity_ids IS NOT NULL AND e.entity_id = ANY(p_prefer_entity_ids) THEN 0 ELSE 1 END,
        -- Then by recency
        e.last_seen DESC NULLS LAST,
        -- Then by confidence
        e.confidence DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION find_entities_by_name IS 'Find entities by name with disambiguation support (prefers active_entity_ids, then recency)';

-- ============================================================================
-- USEFUL QUERIES FOR DIGITAL TWIN MEMORY
-- ============================================================================

-- Get all entities for a user (with optional category filter)
-- SELECT * FROM entities
-- WHERE user_id = 'user-uuid'
--   AND (scope = 'global' OR (scope = 'agent' AND agent_id = 'deanna'))
--   AND category = 'Person'
-- ORDER BY last_seen DESC;

-- Get entity by normalized name
-- SELECT * FROM entities
-- WHERE user_id = 'user-uuid'
--   AND name_normalized = normalize_entity_name('Marta')
--   AND (scope = 'global' OR (scope = 'agent' AND agent_id = 'deanna'));

-- Get all relations for an entity
-- SELECT * FROM get_local_subgraph(
--     'user-uuid'::uuid,
--     'deanna',
--     ARRAY['entity-uuid']::uuid[],
--     40
-- );

-- Get recent episodes for a user/agent
-- SELECT * FROM episodes
-- WHERE user_id = 'user-uuid'
--   AND agent_id = 'deanna'
--   AND active = TRUE
-- ORDER BY ts DESC
-- LIMIT 10;

-- Soft-delete an episode (forgetting)
-- UPDATE episodes SET active = FALSE WHERE episode_id = 'episode-uuid';

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
