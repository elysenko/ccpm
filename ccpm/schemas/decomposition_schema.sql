-- =============================================================================
-- DECOMPOSITION SCHEMA - Autonomous Recursive Implementation
-- =============================================================================
--
-- This schema stores decomposition tree data for recursive feature implementation:
--   - decomposition_sessions: Root session tracking
--   - decomposition_nodes: Tree nodes with hierarchy (layer column)
--   - decomposition_audit_log: Full audit trail of all operations
--
-- Integrates with interview schema via session_name for linking to features.
--
-- =============================================================================

-- =============================================================================
-- TABLE 1: DECOMPOSITION_SESSIONS
-- Root session tracking for autonomous decomposition runs
-- =============================================================================
CREATE TABLE IF NOT EXISTS decomposition_sessions (
    id SERIAL PRIMARY KEY,
    session_name VARCHAR(255) NOT NULL UNIQUE,
    original_request TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'in_progress' CHECK (status IN (
        'in_progress', 'completed', 'failed', 'timeout', 'cancelled'
    )),

    -- Statistics
    total_nodes INTEGER DEFAULT 0,
    leaf_nodes INTEGER DEFAULT 0,
    max_depth INTEGER DEFAULT 0,
    prds_generated INTEGER DEFAULT 0,

    -- Termination tracking
    termination_reason VARCHAR(100),

    -- Timestamps
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE decomposition_sessions IS 'Root session tracking for autonomous decomposition runs';
COMMENT ON COLUMN decomposition_sessions.session_name IS 'Unique session identifier, links to interview schema';
COMMENT ON COLUMN decomposition_sessions.original_request IS 'User''s original feature request text';
COMMENT ON COLUMN decomposition_sessions.status IS 'Session status: in_progress, completed, failed, timeout, cancelled';
COMMENT ON COLUMN decomposition_sessions.termination_reason IS 'Why decomposition stopped: all_atomic, max_depth, max_iterations, timeout, error';

-- =============================================================================
-- TABLE 2: DECOMPOSITION_NODES
-- Tree nodes representing decomposition hierarchy
-- =============================================================================
CREATE TABLE IF NOT EXISTS decomposition_nodes (
    id SERIAL PRIMARY KEY,
    session_name VARCHAR(255) NOT NULL REFERENCES decomposition_sessions(session_name) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES decomposition_nodes(id) ON DELETE CASCADE,

    -- Hierarchy
    layer INTEGER NOT NULL DEFAULT 0,           -- 0=root, 1=gaps, 2=sub-gaps, etc.
    position INTEGER DEFAULT 0,                  -- Order within siblings
    path TEXT,                                   -- Materialized path like "1.2.3"

    -- Content
    name VARCHAR(255) NOT NULL,
    description TEXT,
    gap_type VARCHAR(50) CHECK (gap_type IN (
        'database', 'api', 'frontend', 'backend', 'integration',
        'config', 'migration', 'test', 'documentation', 'other'
    )),
    research_query TEXT,                         -- Query sent to /dr
    research_summary TEXT,                       -- Summary from /dr response

    -- Atomicity assessment
    is_atomic BOOLEAN DEFAULT FALSE,
    estimated_files INTEGER,
    estimated_hours NUMERIC(5,2),
    files_affected TEXT[],                       -- Array of file paths
    complexity VARCHAR(20) CHECK (complexity IN ('trivial', 'simple', 'moderate', 'complex')),

    -- Status
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN (
        'pending', 'researching', 'decomposing', 'atomic', 'prd_generated', 'skipped', 'failed'
    )),
    decomposition_reason TEXT,                   -- Why further decomposition was needed
    skip_reason TEXT,                            -- Why this node was skipped (if applicable)

    -- PRD linkage
    prd_path VARCHAR(500),                       -- Path to generated PRD file
    prd_name VARCHAR(255),                       -- PRD name for /pm:decompose
    prd_generated_at TIMESTAMPTZ,

    -- Context Preservation (for agent handoffs)
    parent_context TEXT,                         -- Summary from parent node for child agents
    codebase_context JSONB,                      -- Relevant codebase findings {files, patterns, integrations}
    decisions JSONB,                             -- Decisions made during decomposition [{decision, rationale, timestamp}]

    -- Gap Analysis (from research)
    gap_signals JSONB,                           -- {linguistic_score, slot_score, codebase_score, confidence_score}
    slot_analysis JSONB,                         -- {goal, trigger, input, output, error_handling, constraints}
    auto_resolved_gaps TEXT[],                   -- Gaps resolved via codebase patterns
    blocking_gaps TEXT[],                        -- Gaps that block implementation
    nice_to_know_gaps TEXT[],                    -- Non-blocking gaps

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE decomposition_nodes IS 'Tree nodes representing decomposition hierarchy';
COMMENT ON COLUMN decomposition_nodes.layer IS 'Tree depth: 0=root, 1=gaps, 2=sub-gaps, etc.';
COMMENT ON COLUMN decomposition_nodes.path IS 'Materialized path for fast tree queries, e.g., "1.2.3"';
COMMENT ON COLUMN decomposition_nodes.gap_type IS 'Type of gap: database, api, frontend, backend, etc.';
COMMENT ON COLUMN decomposition_nodes.is_atomic IS 'True if node is atomic (1-3 files, single responsibility)';
COMMENT ON COLUMN decomposition_nodes.files_affected IS 'Array of file paths this node will modify';
COMMENT ON COLUMN decomposition_nodes.parent_context IS 'Summary context from parent node for agent continuity';
COMMENT ON COLUMN decomposition_nodes.codebase_context IS 'JSON with relevant codebase findings: files, patterns, integrations';
COMMENT ON COLUMN decomposition_nodes.decisions IS 'JSON array of decisions made: [{decision, rationale, timestamp}]';
COMMENT ON COLUMN decomposition_nodes.gap_signals IS 'Gap detection scores: {linguistic, slot_state, codebase, confidence}';
COMMENT ON COLUMN decomposition_nodes.slot_analysis IS 'Slot-filling analysis: {goal, trigger, input, output, error_handling, constraints}';
COMMENT ON COLUMN decomposition_nodes.auto_resolved_gaps IS 'Gaps auto-resolved from codebase patterns';
COMMENT ON COLUMN decomposition_nodes.blocking_gaps IS 'Gaps that block implementation (must resolve)';
COMMENT ON COLUMN decomposition_nodes.nice_to_know_gaps IS 'Non-blocking gaps (can proceed with assumptions)';

-- =============================================================================
-- TABLE 3: DECOMPOSITION_AUDIT_LOG
-- Full audit trail of all decomposition operations
-- =============================================================================
CREATE TABLE IF NOT EXISTS decomposition_audit_log (
    id SERIAL PRIMARY KEY,
    session_name VARCHAR(255) NOT NULL,
    node_id INTEGER REFERENCES decomposition_nodes(id) ON DELETE SET NULL,

    -- Action
    action VARCHAR(50) NOT NULL CHECK (action IN (
        'session_created', 'session_completed', 'session_failed',
        'node_created', 'node_researched', 'node_decomposed', 'node_marked_atomic',
        'prd_generated', 'research_started', 'research_completed',
        'termination_check', 'error'
    )),

    -- Details
    details JSONB,                               -- Action-specific details
    layer INTEGER,                               -- Node layer at time of action
    duration_ms INTEGER,                         -- How long the action took

    -- Error tracking
    error_message TEXT,
    error_stack TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE decomposition_audit_log IS 'Full audit trail of all decomposition operations';
COMMENT ON COLUMN decomposition_audit_log.action IS 'Action type: session_created, node_created, prd_generated, etc.';
COMMENT ON COLUMN decomposition_audit_log.details IS 'JSONB with action-specific details';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Session indexes
CREATE INDEX IF NOT EXISTS idx_decomp_sessions_status ON decomposition_sessions(status);
CREATE INDEX IF NOT EXISTS idx_decomp_sessions_created ON decomposition_sessions(created_at);

-- Node indexes
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_session ON decomposition_nodes(session_name);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_parent ON decomposition_nodes(parent_id);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_layer ON decomposition_nodes(layer);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_atomic ON decomposition_nodes(is_atomic);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_status ON decomposition_nodes(status);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_path ON decomposition_nodes(path);
CREATE INDEX IF NOT EXISTS idx_decomp_nodes_gap_type ON decomposition_nodes(gap_type);

-- Audit log indexes
CREATE INDEX IF NOT EXISTS idx_decomp_audit_session ON decomposition_audit_log(session_name);
CREATE INDEX IF NOT EXISTS idx_decomp_audit_node ON decomposition_audit_log(node_id);
CREATE INDEX IF NOT EXISTS idx_decomp_audit_action ON decomposition_audit_log(action);
CREATE INDEX IF NOT EXISTS idx_decomp_audit_created ON decomposition_audit_log(created_at);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- View: Session summary with tree statistics
CREATE OR REPLACE VIEW decomposition_session_summary AS
SELECT
    ds.id,
    ds.session_name,
    ds.original_request,
    ds.status,
    ds.total_nodes,
    ds.leaf_nodes,
    ds.max_depth,
    ds.prds_generated,
    ds.termination_reason,
    ds.started_at,
    ds.completed_at,
    EXTRACT(EPOCH FROM (COALESCE(ds.completed_at, NOW()) - ds.started_at))::INTEGER AS duration_seconds,
    COUNT(DISTINCT dn.id) FILTER (WHERE dn.is_atomic) AS atomic_count,
    COUNT(DISTINCT dn.id) FILTER (WHERE dn.status = 'prd_generated') AS prd_count
FROM decomposition_sessions ds
LEFT JOIN decomposition_nodes dn ON ds.session_name = dn.session_name
GROUP BY ds.id, ds.session_name, ds.original_request, ds.status,
         ds.total_nodes, ds.leaf_nodes, ds.max_depth, ds.prds_generated,
         ds.termination_reason, ds.started_at, ds.completed_at;

COMMENT ON VIEW decomposition_session_summary IS 'Session summary with calculated tree statistics';

-- View: Node tree with parent info
CREATE OR REPLACE VIEW decomposition_node_tree AS
SELECT
    dn.id,
    dn.session_name,
    dn.parent_id,
    parent.name AS parent_name,
    dn.layer,
    dn.position,
    dn.path,
    dn.name,
    dn.description,
    dn.gap_type,
    dn.is_atomic,
    dn.estimated_files,
    dn.files_affected,
    dn.status,
    dn.prd_path,
    dn.prd_name,
    (SELECT COUNT(*) FROM decomposition_nodes children WHERE children.parent_id = dn.id) AS child_count
FROM decomposition_nodes dn
LEFT JOIN decomposition_nodes parent ON dn.parent_id = parent.id
ORDER BY dn.session_name, dn.path;

COMMENT ON VIEW decomposition_node_tree IS 'Node tree with parent info and child counts';

-- View: Atomic nodes ready for PRD generation
CREATE OR REPLACE VIEW decomposition_atomic_nodes AS
SELECT
    dn.id,
    dn.session_name,
    dn.name,
    dn.description,
    dn.gap_type,
    dn.estimated_files,
    dn.estimated_hours,
    dn.files_affected,
    dn.complexity,
    dn.layer,
    dn.path,
    dn.status,
    dn.prd_path,
    dn.prd_name
FROM decomposition_nodes dn
WHERE dn.is_atomic = TRUE
ORDER BY dn.session_name, dn.layer, dn.position;

COMMENT ON VIEW decomposition_atomic_nodes IS 'Atomic nodes ready for or completed PRD generation';

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function: Create new decomposition session
CREATE OR REPLACE FUNCTION create_decomposition_session(
    p_session_name VARCHAR(255),
    p_original_request TEXT
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO decomposition_sessions (session_name, original_request)
    VALUES (p_session_name, p_original_request)
    RETURNING id INTO v_id;

    -- Log session creation
    INSERT INTO decomposition_audit_log (session_name, action, details)
    VALUES (p_session_name, 'session_created', jsonb_build_object(
        'original_request', p_original_request
    ));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_decomposition_session IS 'Create a new decomposition session with audit logging';

-- Function: Add node to decomposition tree
CREATE OR REPLACE FUNCTION add_decomposition_node(
    p_session_name VARCHAR(255),
    p_parent_id INTEGER,
    p_name VARCHAR(255),
    p_description TEXT,
    p_gap_type VARCHAR(50) DEFAULT NULL,
    p_research_query TEXT DEFAULT NULL,
    p_parent_context TEXT DEFAULT NULL,
    p_codebase_context JSONB DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
    v_layer INTEGER;
    v_position INTEGER;
    v_parent_path TEXT;
    v_path TEXT;
    v_inherited_context TEXT;
BEGIN
    -- Calculate layer
    IF p_parent_id IS NULL THEN
        v_layer := 0;
        v_parent_path := '';
        v_inherited_context := p_parent_context;
    ELSE
        SELECT layer, path, COALESCE(p_parent_context, description)
        INTO v_layer, v_parent_path, v_inherited_context
        FROM decomposition_nodes WHERE id = p_parent_id;
        v_layer := v_layer + 1;
    END IF;

    -- Calculate position within siblings
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
    FROM decomposition_nodes
    WHERE session_name = p_session_name
      AND COALESCE(parent_id, 0) = COALESCE(p_parent_id, 0);

    -- Insert node with context
    INSERT INTO decomposition_nodes (
        session_name, parent_id, layer, position, name, description,
        gap_type, research_query, parent_context, codebase_context
    ) VALUES (
        p_session_name, p_parent_id, v_layer, v_position, p_name, p_description,
        p_gap_type, p_research_query, v_inherited_context, p_codebase_context
    ) RETURNING id INTO v_id;

    -- Update path (now that we have the ID)
    IF v_parent_path = '' THEN
        v_path := v_id::TEXT;
    ELSE
        v_path := v_parent_path || '.' || v_id::TEXT;
    END IF;

    UPDATE decomposition_nodes SET path = v_path WHERE id = v_id;

    -- Update session statistics
    UPDATE decomposition_sessions
    SET total_nodes = total_nodes + 1,
        max_depth = GREATEST(max_depth, v_layer),
        updated_at = NOW()
    WHERE session_name = p_session_name;

    -- Log node creation
    INSERT INTO decomposition_audit_log (session_name, node_id, action, layer, details)
    VALUES (p_session_name, v_id, 'node_created', v_layer, jsonb_build_object(
        'name', p_name,
        'parent_id', p_parent_id,
        'gap_type', p_gap_type,
        'has_parent_context', p_parent_context IS NOT NULL,
        'has_codebase_context', p_codebase_context IS NOT NULL
    ));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION add_decomposition_node IS 'Add a node to the decomposition tree with automatic path calculation';

-- Function: Mark node as atomic
CREATE OR REPLACE FUNCTION mark_node_atomic(
    p_node_id INTEGER,
    p_estimated_files INTEGER,
    p_estimated_hours NUMERIC,
    p_files_affected TEXT[],
    p_complexity VARCHAR(20) DEFAULT 'moderate'
) RETURNS VOID AS $$
DECLARE
    v_session_name VARCHAR(255);
    v_layer INTEGER;
BEGIN
    -- Get session name and layer
    SELECT session_name, layer INTO v_session_name, v_layer
    FROM decomposition_nodes WHERE id = p_node_id;

    -- Update node
    UPDATE decomposition_nodes
    SET is_atomic = TRUE,
        estimated_files = p_estimated_files,
        estimated_hours = p_estimated_hours,
        files_affected = p_files_affected,
        complexity = p_complexity,
        status = 'atomic',
        updated_at = NOW()
    WHERE id = p_node_id;

    -- Update session leaf count
    UPDATE decomposition_sessions
    SET leaf_nodes = leaf_nodes + 1,
        updated_at = NOW()
    WHERE session_name = v_session_name;

    -- Log
    INSERT INTO decomposition_audit_log (session_name, node_id, action, layer, details)
    VALUES (v_session_name, p_node_id, 'node_marked_atomic', v_layer, jsonb_build_object(
        'estimated_files', p_estimated_files,
        'estimated_hours', p_estimated_hours,
        'files_affected', p_files_affected,
        'complexity', p_complexity
    ));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mark_node_atomic IS 'Mark a decomposition node as atomic (leaf node)';

-- Function: Record PRD generation
CREATE OR REPLACE FUNCTION record_prd_generation(
    p_node_id INTEGER,
    p_prd_path VARCHAR(500),
    p_prd_name VARCHAR(255)
) RETURNS VOID AS $$
DECLARE
    v_session_name VARCHAR(255);
    v_layer INTEGER;
BEGIN
    -- Get session name and layer
    SELECT session_name, layer INTO v_session_name, v_layer
    FROM decomposition_nodes WHERE id = p_node_id;

    -- Update node
    UPDATE decomposition_nodes
    SET prd_path = p_prd_path,
        prd_name = p_prd_name,
        prd_generated_at = NOW(),
        status = 'prd_generated',
        updated_at = NOW()
    WHERE id = p_node_id;

    -- Update session PRD count
    UPDATE decomposition_sessions
    SET prds_generated = prds_generated + 1,
        updated_at = NOW()
    WHERE session_name = v_session_name;

    -- Log
    INSERT INTO decomposition_audit_log (session_name, node_id, action, layer, details)
    VALUES (v_session_name, p_node_id, 'prd_generated', v_layer, jsonb_build_object(
        'prd_path', p_prd_path,
        'prd_name', p_prd_name
    ));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION record_prd_generation IS 'Record PRD generation for an atomic node';

-- Function: Complete session
CREATE OR REPLACE FUNCTION complete_decomposition_session(
    p_session_name VARCHAR(255),
    p_termination_reason VARCHAR(100),
    p_status VARCHAR(50) DEFAULT 'completed'
) RETURNS VOID AS $$
BEGIN
    UPDATE decomposition_sessions
    SET status = p_status,
        termination_reason = p_termination_reason,
        completed_at = NOW(),
        updated_at = NOW()
    WHERE session_name = p_session_name;

    -- Log
    INSERT INTO decomposition_audit_log (session_name, action, details)
    VALUES (p_session_name,
            CASE p_status WHEN 'completed' THEN 'session_completed' ELSE 'session_failed' END,
            jsonb_build_object(
                'termination_reason', p_termination_reason,
                'status', p_status
            ));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION complete_decomposition_session IS 'Complete a decomposition session with termination reason';

-- Function: Get pending non-atomic nodes for decomposition
CREATE OR REPLACE FUNCTION get_pending_nodes(
    p_session_name VARCHAR(255)
) RETURNS TABLE (
    id INTEGER,
    name VARCHAR(255),
    description TEXT,
    layer INTEGER,
    parent_id INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT dn.id, dn.name, dn.description, dn.layer, dn.parent_id
    FROM decomposition_nodes dn
    WHERE dn.session_name = p_session_name
      AND dn.is_atomic = FALSE
      AND dn.status IN ('pending', 'researching')
    ORDER BY dn.layer, dn.position;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_pending_nodes IS 'Get pending non-atomic nodes that need decomposition';

-- Function: Get tree as nested JSON
CREATE OR REPLACE FUNCTION get_decomposition_tree(
    p_session_name VARCHAR(255)
) RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    WITH RECURSIVE tree AS (
        -- Root nodes
        SELECT
            id, name, description, gap_type, is_atomic, status, prd_path,
            layer, path, 1 AS depth,
            jsonb_build_object(
                'id', id,
                'name', name,
                'description', description,
                'gap_type', gap_type,
                'is_atomic', is_atomic,
                'status', status,
                'prd_path', prd_path,
                'layer', layer
            ) AS node_json
        FROM decomposition_nodes
        WHERE session_name = p_session_name AND parent_id IS NULL

        UNION ALL

        -- Child nodes
        SELECT
            n.id, n.name, n.description, n.gap_type, n.is_atomic, n.status, n.prd_path,
            n.layer, n.path, t.depth + 1,
            jsonb_build_object(
                'id', n.id,
                'name', n.name,
                'description', n.description,
                'gap_type', n.gap_type,
                'is_atomic', n.is_atomic,
                'status', n.status,
                'prd_path', n.prd_path,
                'layer', n.layer
            )
        FROM decomposition_nodes n
        JOIN tree t ON n.parent_id = t.id
        WHERE n.session_name = p_session_name
    )
    SELECT jsonb_agg(node_json ORDER BY path) INTO v_result FROM tree;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_decomposition_tree IS 'Get entire decomposition tree as JSON';

-- Function: Update node gap analysis (from research-based gap detection)
CREATE OR REPLACE FUNCTION update_node_gap_analysis(
    p_node_id INTEGER,
    p_gap_signals JSONB,
    p_slot_analysis JSONB,
    p_auto_resolved TEXT[],
    p_blocking TEXT[],
    p_nice_to_know TEXT[]
) RETURNS VOID AS $$
DECLARE
    v_session_name VARCHAR(255);
BEGIN
    -- Get session name
    SELECT session_name INTO v_session_name
    FROM decomposition_nodes WHERE id = p_node_id;

    -- Update node
    UPDATE decomposition_nodes
    SET gap_signals = p_gap_signals,
        slot_analysis = p_slot_analysis,
        auto_resolved_gaps = p_auto_resolved,
        blocking_gaps = p_blocking,
        nice_to_know_gaps = p_nice_to_know,
        updated_at = NOW()
    WHERE id = p_node_id;

    -- Log
    INSERT INTO decomposition_audit_log (session_name, node_id, action, details)
    VALUES (v_session_name, p_node_id, 'node_researched', jsonb_build_object(
        'gap_signals', p_gap_signals,
        'blocking_count', COALESCE(array_length(p_blocking, 1), 0),
        'auto_resolved_count', COALESCE(array_length(p_auto_resolved, 1), 0)
    ));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_node_gap_analysis IS 'Update node with gap analysis results from multi-signal detection';

-- Function: Record decision made during decomposition
CREATE OR REPLACE FUNCTION record_node_decision(
    p_node_id INTEGER,
    p_decision TEXT,
    p_rationale TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE decomposition_nodes
    SET decisions = COALESCE(decisions, '[]'::jsonb) || jsonb_build_object(
            'decision', p_decision,
            'rationale', p_rationale,
            'timestamp', NOW()
        ),
        updated_at = NOW()
    WHERE id = p_node_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION record_node_decision IS 'Record a decision made during decomposition for audit trail';

-- Function: Get node with full context for agent handoff
CREATE OR REPLACE FUNCTION get_node_with_context(
    p_node_id INTEGER
) RETURNS TABLE (
    id INTEGER,
    session_name VARCHAR(255),
    name VARCHAR(255),
    description TEXT,
    gap_type VARCHAR(50),
    layer INTEGER,
    parent_context TEXT,
    codebase_context JSONB,
    decisions JSONB,
    gap_signals JSONB,
    slot_analysis JSONB,
    blocking_gaps TEXT[],
    status VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        dn.id,
        dn.session_name,
        dn.name,
        dn.description,
        dn.gap_type,
        dn.layer,
        dn.parent_context,
        dn.codebase_context,
        dn.decisions,
        dn.gap_signals,
        dn.slot_analysis,
        dn.blocking_gaps,
        dn.status
    FROM decomposition_nodes dn
    WHERE dn.id = p_node_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_node_with_context IS 'Get node with full context for agent handoff';

-- =============================================================================
-- SCHEMA VERSION
-- =============================================================================
COMMENT ON SCHEMA public IS 'Decomposition Schema v1.0.0 - Added to Interview Schema for autonomous recursive implementation';
