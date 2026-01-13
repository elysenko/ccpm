-- =============================================================================
-- INTERVIEW SCHEMA - Conversation-to-Implementation Tracking
-- =============================================================================
--
-- This schema stores the complete interrogation-to-implementation lifecycle:
-- - Raw conversation storage with Q&A turn tracking
-- - Linking conversation turns to extracted insights
-- - Detailed user journey steps with technical implementation details
-- - Backend action tracing (frontend → API → service → DB)
--
-- Architecture:
--   Section 1: Sessions & Conversations (4 tables)
--   Section 2: Enhanced User Journeys (4 tables)
--   Section 3: Technical Component Mapping (5 tables)
--   Section 4: Implementation Tracing (3 tables)
--
-- Total: 16 tables, 5 views, 2 functions
-- =============================================================================

-- =============================================================================
-- SECTION 1: INTERROGATION SESSIONS & CONVERSATIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table 1: Interrogation Sessions (Master session container)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS interrogation_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID,
    session_name VARCHAR(255) NOT NULL,
    session_type VARCHAR(50) NOT NULL DEFAULT 'solution' CHECK (session_type IN (
        'problem', 'solution', 'research', 'feature', 'decision', 'process'
    )),
    domain VARCHAR(50) NOT NULL DEFAULT 'technical' CHECK (domain IN (
        'technical', 'business', 'creative', 'research', 'operational'
    )),
    status VARCHAR(20) DEFAULT 'in_progress' CHECK (status IN (
        'in_progress', 'paused', 'complete', 'abandoned'
    )),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ DEFAULT NOW(),
    source_file_path TEXT,
    total_turns INTEGER DEFAULT 0,
    features_extracted INTEGER DEFAULT 0,
    journeys_extracted INTEGER DEFAULT 0,
    created_by VARCHAR(100) DEFAULT 'interrogation_agent',
    metadata JSONB DEFAULT '{}',
    UNIQUE(project_id, session_name)
);

CREATE INDEX IF NOT EXISTS idx_interrogation_sessions_project ON interrogation_sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_interrogation_sessions_status ON interrogation_sessions(status);
CREATE INDEX IF NOT EXISTS idx_interrogation_sessions_type ON interrogation_sessions(session_type, domain);

COMMENT ON TABLE interrogation_sessions IS 'Master container for interrogation/interview sessions';
COMMENT ON COLUMN interrogation_sessions.session_type IS 'Classification: problem, solution, research, feature, decision, process';
COMMENT ON COLUMN interrogation_sessions.domain IS 'Domain classification: technical, business, creative, research, operational';

-- -----------------------------------------------------------------------------
-- Table 2: Conversation Turns (Individual Q&A exchanges)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversation_turns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    turn_number INTEGER NOT NULL CHECK (turn_number > 0),
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    question_layer VARCHAR(50) CHECK (question_layer IN (
        'context', 'type_specific', 'domain_specific',
        'feature_discovery', 'journey_mapping', 'clarification', 'confirmation'
    )),
    question_topic VARCHAR(255),
    contains_feature_info BOOLEAN DEFAULT FALSE,
    contains_journey_info BOOLEAN DEFAULT FALSE,
    contains_constraint_info BOOLEAN DEFAULT FALSE,
    contains_decision BOOLEAN DEFAULT FALSE,
    response_type VARCHAR(50) CHECK (response_type IN (
        'direct_answer', 'clarification', 'deferral', 'i_dont_know',
        'confirmation', 'correction', 'elaboration', 'question'
    )),
    confidence_indicator VARCHAR(20) CHECK (confidence_indicator IN (
        'high', 'medium', 'low', 'unknown'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    requires_research BOOLEAN DEFAULT FALSE,
    research_topic TEXT,
    research_completed BOOLEAN DEFAULT FALSE,
    UNIQUE(session_id, turn_number)
);

CREATE INDEX IF NOT EXISTS idx_conversation_turns_session ON conversation_turns(session_id, turn_number);
CREATE INDEX IF NOT EXISTS idx_conversation_turns_role ON conversation_turns(role);
CREATE INDEX IF NOT EXISTS idx_conversation_turns_feature ON conversation_turns(contains_feature_info) WHERE contains_feature_info = TRUE;
CREATE INDEX IF NOT EXISTS idx_conversation_turns_journey ON conversation_turns(contains_journey_info) WHERE contains_journey_info = TRUE;
CREATE INDEX IF NOT EXISTS idx_conversation_turns_research ON conversation_turns(requires_research) WHERE requires_research = TRUE;

COMMENT ON TABLE conversation_turns IS 'Individual Q&A turns in the interrogation conversation';
COMMENT ON COLUMN conversation_turns.question_layer IS 'Which discovery layer this question belongs to (per /pm:interrogate)';
COMMENT ON COLUMN conversation_turns.response_type IS 'How the user responded: direct answer, deferral, i_dont_know, etc.';

-- -----------------------------------------------------------------------------
-- Table 3: Turn Extractions (Insights extracted from turns)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS turn_extractions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    turn_id UUID NOT NULL REFERENCES conversation_turns(id) ON DELETE CASCADE,
    extraction_type VARCHAR(50) NOT NULL CHECK (extraction_type IN (
        'feature', 'journey', 'journey_step', 'constraint', 'success_criterion',
        'risk', 'decision', 'assumption', 'stakeholder', 'integration',
        'nfr_performance', 'nfr_security', 'nfr_scalability', 'nfr_compliance',
        'tech_stack_preference', 'timeline', 'budget', 'unknown'
    )),
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID NOT NULL,
    verbatim_quote TEXT,
    confidence FLOAT DEFAULT 1.0 CHECK (confidence BETWEEN 0 AND 1),
    extraction_method VARCHAR(50) DEFAULT 'llm' CHECK (extraction_method IN (
        'llm', 'pattern', 'explicit', 'inferred'
    )),
    validated BOOLEAN DEFAULT FALSE,
    validated_at TIMESTAMPTZ,
    validated_by VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_turn_extractions_turn ON turn_extractions(turn_id);
CREATE INDEX IF NOT EXISTS idx_turn_extractions_type ON turn_extractions(extraction_type);
CREATE INDEX IF NOT EXISTS idx_turn_extractions_entity ON turn_extractions(entity_type, entity_id);

COMMENT ON TABLE turn_extractions IS 'Links conversation turns to extracted entities for full traceability';
COMMENT ON COLUMN turn_extractions.verbatim_quote IS 'Exact quote from conversation supporting this extraction';

-- -----------------------------------------------------------------------------
-- Table 4: Extraction Conflicts (Contradictions and Ambiguities)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS extraction_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    extraction_a_id UUID NOT NULL REFERENCES turn_extractions(id) ON DELETE CASCADE,
    extraction_b_id UUID NOT NULL REFERENCES turn_extractions(id) ON DELETE CASCADE,
    conflict_type VARCHAR(50) NOT NULL CHECK (conflict_type IN (
        'contradiction', 'ambiguity', 'incomplete', 'superseded'
    )),
    description TEXT NOT NULL,
    resolution_status VARCHAR(20) DEFAULT 'unresolved' CHECK (resolution_status IN (
        'unresolved', 'resolved', 'deferred', 'accepted_both'
    )),
    resolution_notes TEXT,
    winning_extraction_id UUID REFERENCES turn_extractions(id),
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_extraction_conflicts_session ON extraction_conflicts(session_id);
CREATE INDEX IF NOT EXISTS idx_extraction_conflicts_status ON extraction_conflicts(resolution_status) WHERE resolution_status = 'unresolved';

COMMENT ON TABLE extraction_conflicts IS 'Tracks contradictions and ambiguities between extractions';

-- =============================================================================
-- SECTION 2: ENHANCED USER JOURNEYS WITH DETAILED STEPS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table 5: User Journeys Enhanced
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_journeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    qa_session_id UUID,
    journey_id VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    actor_type VARCHAR(100) NOT NULL,
    actor_description TEXT,
    persona_id UUID,
    user_type_id UUID,
    trigger_event TEXT NOT NULL,
    goal TEXT NOT NULL,
    preconditions TEXT[],
    postconditions TEXT[],
    estimated_duration VARCHAR(50),
    frequency VARCHAR(50) CHECK (frequency IN (
        'multiple_daily', 'daily', 'weekly', 'monthly', 'occasional', 'rare'
    )),
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN (
        'critical', 'high', 'medium', 'low'
    )),
    complexity VARCHAR(20) DEFAULT 'medium' CHECK (complexity IN (
        'simple', 'medium', 'complex', 'very_complex'
    )),
    exception_paths JSONB DEFAULT '[]',
    error_handling_notes TEXT,
    success_criteria TEXT[],
    related_feature_ids UUID[] DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN (
        'draft', 'pending_review', 'approved', 'implemented', 'deprecated'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    version INTEGER DEFAULT 1,
    UNIQUE(session_id, journey_id)
);

CREATE INDEX IF NOT EXISTS idx_user_journeys_session ON user_journeys(session_id);
CREATE INDEX IF NOT EXISTS idx_user_journeys_actor ON user_journeys(actor_type);
CREATE INDEX IF NOT EXISTS idx_user_journeys_priority ON user_journeys(priority);
CREATE INDEX IF NOT EXISTS idx_user_journeys_status ON user_journeys(status);

COMMENT ON TABLE user_journeys IS 'User journeys extracted from interrogation with full metadata';
COMMENT ON COLUMN user_journeys.journey_id IS 'Human-readable ID like J-001, J-002';

-- -----------------------------------------------------------------------------
-- Table 6: Journey Steps Detailed (The core detailed step table)
-- -----------------------------------------------------------------------------
-- Each step captures: user action, UI, frontend event, API, backend, DB
CREATE TABLE IF NOT EXISTS journey_steps_detailed (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journey_id UUID NOT NULL REFERENCES user_journeys(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL CHECK (step_number > 0),
    step_name VARCHAR(255) NOT NULL,
    step_description TEXT,

    -- USER LAYER
    user_action TEXT NOT NULL,
    user_intent TEXT,
    user_decision_point BOOLEAN DEFAULT FALSE,
    decision_options JSONB,

    -- UI LAYER
    ui_component_type VARCHAR(100),
    ui_component_name VARCHAR(255),
    ui_component_location TEXT,
    ui_page_route VARCHAR(500),
    ui_state_before JSONB,
    ui_state_after JSONB,
    ui_validation_rules JSONB,
    ui_feedback TEXT,

    -- FRONTEND EVENT LAYER
    frontend_event_type VARCHAR(100),
    frontend_event_name VARCHAR(255),
    frontend_event_payload JSONB,
    frontend_state_change JSONB,

    -- API LAYER
    api_protocol VARCHAR(50) DEFAULT 'graphql' CHECK (api_protocol IN (
        'graphql', 'rest', 'grpc', 'websocket', 'none'
    )),
    api_operation_type VARCHAR(50) CHECK (api_operation_type IN (
        'query', 'mutation', 'subscription',
        'GET', 'POST', 'PUT', 'PATCH', 'DELETE',
        'unary', 'stream', 'message', 'none'
    )),
    api_operation_name VARCHAR(255),
    api_endpoint VARCHAR(500),
    api_request_schema JSONB,
    api_response_schema JSONB,
    api_headers JSONB,
    api_auth_required BOOLEAN DEFAULT TRUE,
    api_rate_limited BOOLEAN DEFAULT FALSE,

    -- BACKEND SERVICE LAYER
    backend_resolver VARCHAR(255),
    backend_service VARCHAR(255),
    backend_method VARCHAR(255),
    backend_input_dto VARCHAR(255),
    backend_output_dto VARCHAR(255),

    -- BUSINESS LOGIC LAYER
    business_rules JSONB,
    validation_rules JSONB,
    transformation_logic TEXT,
    side_effects TEXT[],

    -- DATA ACCESS LAYER
    repository VARCHAR(255),
    repository_method VARCHAR(255),

    -- DATABASE LAYER
    db_operation VARCHAR(50) CHECK (db_operation IN (
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'UPSERT', 'NONE', 'MULTIPLE'
    )),
    db_tables_affected TEXT[],
    db_entities_affected TEXT[],
    db_fields_read TEXT[],
    db_fields_written TEXT[],
    db_transaction_required BOOLEAN DEFAULT FALSE,
    db_isolation_level VARCHAR(50),

    -- RESPONSE FLOW
    response_to_frontend JSONB,
    ui_update_triggered TEXT,
    next_step_condition TEXT,

    -- ERROR HANDLING
    possible_errors JSONB,
    error_ui_display TEXT,
    rollback_behavior TEXT,

    -- ASYNC/BACKGROUND
    is_async BOOLEAN DEFAULT FALSE,
    background_job_type VARCHAR(100),
    polling_required BOOLEAN DEFAULT FALSE,
    webhook_triggered BOOLEAN DEFAULT FALSE,

    -- METADATA
    estimated_duration_ms INTEGER,
    is_optional BOOLEAN DEFAULT FALSE,
    is_automated BOOLEAN DEFAULT FALSE,
    requires_confirmation BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(journey_id, step_number)
);

CREATE INDEX IF NOT EXISTS idx_journey_steps_journey ON journey_steps_detailed(journey_id, step_number);
CREATE INDEX IF NOT EXISTS idx_journey_steps_component ON journey_steps_detailed(ui_component_type);
CREATE INDEX IF NOT EXISTS idx_journey_steps_api ON journey_steps_detailed(api_operation_name);
CREATE INDEX IF NOT EXISTS idx_journey_steps_service ON journey_steps_detailed(backend_service);
CREATE INDEX IF NOT EXISTS idx_journey_steps_db_op ON journey_steps_detailed(db_operation);
CREATE INDEX IF NOT EXISTS idx_journey_steps_ui_route ON journey_steps_detailed(ui_page_route);
CREATE INDEX IF NOT EXISTS idx_journey_steps_service_method ON journey_steps_detailed(backend_service, backend_method);

COMMENT ON TABLE journey_steps_detailed IS 'Detailed journey steps with full technical implementation spec';
COMMENT ON COLUMN journey_steps_detailed.ui_component_type IS 'Type of UI component: button, form, table, modal, page';
COMMENT ON COLUMN journey_steps_detailed.api_operation_name IS 'GraphQL mutation/query name or REST endpoint action';
COMMENT ON COLUMN journey_steps_detailed.backend_service IS 'Backend service class handling this step';
COMMENT ON COLUMN journey_steps_detailed.db_operation IS 'Primary database operation: SELECT, INSERT, UPDATE, DELETE';

-- -----------------------------------------------------------------------------
-- Table 7: Step Data Flow (Track data through each step)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS step_data_flow (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    data_name VARCHAR(255) NOT NULL,
    data_type VARCHAR(100) NOT NULL,
    source_layer VARCHAR(50) NOT NULL CHECK (source_layer IN (
        'user_input', 'ui_state', 'frontend_state', 'api_request',
        'backend_context', 'database', 'external_service', 'computed'
    )),
    target_layer VARCHAR(50) NOT NULL CHECK (target_layer IN (
        'ui_display', 'frontend_state', 'api_response',
        'backend_state', 'database', 'external_service', 'side_effect'
    )),
    transformation_applied TEXT,
    validation_rule TEXT,
    is_sensitive BOOLEAN DEFAULT FALSE,
    sensitivity_type VARCHAR(50) CHECK (sensitivity_type IN (
        'pii', 'financial', 'credential', 'internal', 'public'
    )),
    encryption_required BOOLEAN DEFAULT FALSE,
    audit_logged BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_step_data_flow_step ON step_data_flow(step_id);
CREATE INDEX IF NOT EXISTS idx_step_data_flow_data ON step_data_flow(data_name);
CREATE INDEX IF NOT EXISTS idx_step_data_flow_sensitive ON step_data_flow(is_sensitive) WHERE is_sensitive = TRUE;

COMMENT ON TABLE step_data_flow IS 'Tracks how data flows through each step across layers';

-- -----------------------------------------------------------------------------
-- Table 8: Step Dependencies (Between journey steps)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS step_dependencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    depends_on_step_id UUID NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    dependency_type VARCHAR(50) NOT NULL CHECK (dependency_type IN (
        'sequential', 'data', 'state', 'conditional', 'parallel_ok'
    )),
    condition_expression TEXT,
    is_blocking BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(step_id, depends_on_step_id),
    CHECK(step_id != depends_on_step_id)
);

CREATE INDEX IF NOT EXISTS idx_step_dependencies_step ON step_dependencies(step_id);
CREATE INDEX IF NOT EXISTS idx_step_dependencies_depends ON step_dependencies(depends_on_step_id);

COMMENT ON TABLE step_dependencies IS 'Dependencies between journey steps';

-- =============================================================================
-- SECTION 3: TECHNICAL COMPONENT MAPPING
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table 9: Features (From extract-findings)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    feature_id VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    user_story_as_a VARCHAR(255),
    user_story_i_want TEXT,
    user_story_so_that TEXT,
    priority VARCHAR(50) DEFAULT 'should_have' CHECK (priority IN (
        'must_have', 'should_have', 'could_have', 'wont_have'
    )),
    acceptance_criteria JSONB DEFAULT '[]',
    stakeholder_source VARCHAR(255),
    evidence_quote TEXT,
    confidence VARCHAR(20) DEFAULT 'medium' CHECK (confidence IN ('high', 'medium', 'low')),
    complexity VARCHAR(20) CHECK (complexity IN (
        'trivial', 'simple', 'medium', 'complex', 'very_complex'
    )),
    effort_estimate VARCHAR(50),
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN (
        'draft', 'pending_review', 'approved', 'in_development', 'implemented', 'deprecated'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(session_id, feature_id)
);

CREATE INDEX IF NOT EXISTS idx_features_session ON features(session_id);
CREATE INDEX IF NOT EXISTS idx_features_priority ON features(priority);
CREATE INDEX IF NOT EXISTS idx_features_status ON features(status);

COMMENT ON TABLE features IS 'Features extracted from interrogation conversations';

-- -----------------------------------------------------------------------------
-- Table 10: Feature-Journey Mapping
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feature_journey_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_id UUID NOT NULL REFERENCES features(id) ON DELETE CASCADE,
    journey_id UUID NOT NULL REFERENCES user_journeys(id) ON DELETE CASCADE,
    relationship_type VARCHAR(50) DEFAULT 'implements' CHECK (relationship_type IN (
        'implements', 'uses', 'extends', 'depends_on'
    )),
    journey_step_ids UUID[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(feature_id, journey_id)
);

CREATE INDEX IF NOT EXISTS idx_feature_journey_feature ON feature_journey_mapping(feature_id);
CREATE INDEX IF NOT EXISTS idx_feature_journey_journey ON feature_journey_mapping(journey_id);

COMMENT ON TABLE feature_journey_mapping IS 'Maps features to the journeys that implement them';

-- -----------------------------------------------------------------------------
-- Table 11: Technical Components (From architecture analysis)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS technical_components (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    component_type VARCHAR(50) NOT NULL CHECK (component_type IN (
        'ui_page', 'ui_component', 'frontend_service', 'frontend_store',
        'api_endpoint', 'graphql_type', 'graphql_resolver', 'graphql_mutation', 'graphql_query',
        'backend_service', 'backend_repository', 'backend_dto', 'backend_entity',
        'database_table', 'database_view', 'database_function',
        'external_integration', 'message_queue', 'background_job'
    )),
    component_name VARCHAR(255) NOT NULL,
    component_path TEXT,
    description TEXT,
    specifications JSONB DEFAULT '{}',
    depends_on_component_ids UUID[] DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN (
        'planned', 'designed', 'implemented', 'tested', 'deployed'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_technical_components_session ON technical_components(session_id);
CREATE INDEX IF NOT EXISTS idx_technical_components_type ON technical_components(component_type);

COMMENT ON TABLE technical_components IS 'Technical components identified from architecture analysis';

-- -----------------------------------------------------------------------------
-- Table 12: Step-Component Mapping
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS step_component_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    component_id UUID NOT NULL REFERENCES technical_components(id) ON DELETE CASCADE,
    usage_type VARCHAR(50) NOT NULL CHECK (usage_type IN (
        'renders', 'calls', 'reads', 'writes', 'creates', 'updates', 'deletes', 'triggers'
    )),
    usage_order INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(step_id, component_id, usage_type)
);

CREATE INDEX IF NOT EXISTS idx_step_component_step ON step_component_mapping(step_id);
CREATE INDEX IF NOT EXISTS idx_step_component_component ON step_component_mapping(component_id);

COMMENT ON TABLE step_component_mapping IS 'Maps journey steps to technical components';

-- -----------------------------------------------------------------------------
-- Table 13: Database Entities (Entities affected by journeys)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS database_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES interrogation_sessions(id) ON DELETE CASCADE,
    entity_name VARCHAR(255) NOT NULL,
    table_name VARCHAR(255),
    schema_definition JSONB,
    primary_key VARCHAR(255),
    indexes JSONB DEFAULT '[]',
    constraints JSONB DEFAULT '[]',
    relationships JSONB DEFAULT '[]',
    description TEXT,
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN (
        'planned', 'designed', 'migrated', 'populated'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(session_id, entity_name)
);

CREATE INDEX IF NOT EXISTS idx_database_entities_session ON database_entities(session_id);
CREATE INDEX IF NOT EXISTS idx_database_entities_table ON database_entities(table_name);

COMMENT ON TABLE database_entities IS 'Database entities/tables identified from scope analysis';

-- =============================================================================
-- SECTION 4: IMPLEMENTATION TRACING (Backend Action Flow)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table 14: Backend Action Traces (Full request/response flow)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS backend_action_traces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    trace_name VARCHAR(255) NOT NULL,
    trace_description TEXT,
    request_entry_point VARCHAR(255),
    request_payload_schema JSONB,
    response_exit_point VARCHAR(255),
    response_payload_schema JSONB,
    error_scenarios JSONB DEFAULT '[]',
    expected_latency_ms INTEGER,
    timeout_ms INTEGER,
    transaction_boundary VARCHAR(50) CHECK (transaction_boundary IN (
        'none', 'step', 'trace', 'saga'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_backend_traces_step ON backend_action_traces(step_id);

COMMENT ON TABLE backend_action_traces IS 'Captures the full backend action flow for each step';

-- -----------------------------------------------------------------------------
-- Table 15: Trace Layers (Individual layers in the trace)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trace_layers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trace_id UUID NOT NULL REFERENCES backend_action_traces(id) ON DELETE CASCADE,
    layer_order INTEGER NOT NULL CHECK (layer_order > 0),
    layer_type VARCHAR(50) NOT NULL CHECK (layer_type IN (
        'graphql_resolver', 'rest_controller', 'grpc_handler',
        'service', 'domain_service', 'application_service',
        'repository', 'data_mapper',
        'database', 'cache',
        'external_api', 'message_queue', 'event_bus'
    )),
    layer_name VARCHAR(255) NOT NULL,
    method_name VARCHAR(255),
    input_type VARCHAR(255),
    input_schema JSONB,
    output_type VARCHAR(255),
    output_schema JSONB,
    business_logic_description TEXT,
    validation_rules JSONB DEFAULT '[]',
    transformations JSONB DEFAULT '[]',
    side_effects JSONB DEFAULT '[]',
    error_handling JSONB,
    expected_latency_contribution_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(trace_id, layer_order)
);

CREATE INDEX IF NOT EXISTS idx_trace_layers_trace ON trace_layers(trace_id, layer_order);
CREATE INDEX IF NOT EXISTS idx_trace_layers_type ON trace_layers(layer_type);

COMMENT ON TABLE trace_layers IS 'Individual layers in the backend action trace';

-- -----------------------------------------------------------------------------
-- Table 16: Entity Operations (CRUD operations per trace)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entity_operations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trace_layer_id UUID NOT NULL REFERENCES trace_layers(id) ON DELETE CASCADE,
    entity_id UUID REFERENCES database_entities(id) ON DELETE SET NULL,
    entity_name VARCHAR(255) NOT NULL,
    operation_type VARCHAR(20) NOT NULL CHECK (operation_type IN (
        'CREATE', 'READ', 'UPDATE', 'DELETE', 'UPSERT',
        'BULK_CREATE', 'BULK_UPDATE', 'BULK_DELETE'
    )),
    fields_affected TEXT[],
    filter_criteria JSONB,
    sort_order JSONB,
    pagination JSONB,
    requires_transaction BOOLEAN DEFAULT FALSE,
    isolation_level VARCHAR(50),
    lock_type VARCHAR(50) CHECK (lock_type IN ('none', 'row', 'table', 'advisory')),
    cascade_effects JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entity_operations_layer ON entity_operations(trace_layer_id);
CREATE INDEX IF NOT EXISTS idx_entity_operations_entity ON entity_operations(entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_operations_type ON entity_operations(operation_type);

COMMENT ON TABLE entity_operations IS 'Database operations performed at each layer';

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- View: Full Journey with Steps (For API consumption)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW journey_full_view AS
SELECT
    j.id AS journey_id,
    j.journey_id AS journey_code,
    j.name AS journey_name,
    j.actor_type,
    j.trigger_event,
    j.goal,
    j.priority,
    j.frequency,
    j.status,
    s.session_name,
    s.session_type,
    s.domain,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE journey_id = j.id) AS total_steps,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE journey_id = j.id AND is_optional = FALSE) AS required_steps,
    (SELECT COUNT(DISTINCT db_operation) FROM journey_steps_detailed WHERE journey_id = j.id AND db_operation != 'NONE') AS unique_db_operations,
    (SELECT COUNT(DISTINCT backend_service) FROM journey_steps_detailed WHERE journey_id = j.id AND backend_service IS NOT NULL) AS unique_services,
    (
        SELECT jsonb_agg(jsonb_build_object(
            'step_number', js.step_number,
            'step_name', js.step_name,
            'user_action', js.user_action,
            'ui_component', js.ui_component_type || ': ' || COALESCE(js.ui_component_name, 'N/A'),
            'api_operation', js.api_operation_name,
            'backend_service', js.backend_service,
            'db_operation', js.db_operation,
            'db_tables', js.db_tables_affected
        ) ORDER BY js.step_number)
        FROM journey_steps_detailed js
        WHERE js.journey_id = j.id
    ) AS steps
FROM user_journeys j
JOIN interrogation_sessions s ON s.id = j.session_id;

COMMENT ON VIEW journey_full_view IS 'Complete journey with all steps for API consumption';

-- -----------------------------------------------------------------------------
-- View: Step Technical Summary (For developers)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW step_technical_summary AS
SELECT
    js.id AS step_id,
    j.journey_id AS journey_code,
    j.name AS journey_name,
    js.step_number,
    js.step_name,
    js.user_action,
    js.ui_component_type,
    js.ui_component_name,
    js.ui_page_route,
    js.api_protocol,
    js.api_operation_type,
    js.api_operation_name,
    js.backend_resolver,
    js.backend_service,
    js.backend_method,
    js.repository,
    js.db_operation,
    js.db_tables_affected,
    js.db_fields_written,
    js.is_async,
    js.requires_confirmation,
    js.is_automated
FROM journey_steps_detailed js
JOIN user_journeys j ON j.id = js.journey_id
ORDER BY j.journey_id, js.step_number;

COMMENT ON VIEW step_technical_summary IS 'Technical summary of each step for developers';

-- -----------------------------------------------------------------------------
-- View: Conversation Extraction Summary
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW extraction_summary AS
SELECT
    s.id AS session_id,
    s.session_name,
    s.session_type,
    s.domain,
    s.status,
    s.total_turns,
    (SELECT COUNT(*) FROM turn_extractions te
     JOIN conversation_turns ct ON ct.id = te.turn_id
     WHERE ct.session_id = s.id AND te.extraction_type = 'feature') AS features_extracted,
    (SELECT COUNT(*) FROM turn_extractions te
     JOIN conversation_turns ct ON ct.id = te.turn_id
     WHERE ct.session_id = s.id AND te.extraction_type = 'journey') AS journeys_extracted,
    (SELECT COUNT(*) FROM turn_extractions te
     JOIN conversation_turns ct ON ct.id = te.turn_id
     WHERE ct.session_id = s.id AND te.extraction_type = 'constraint') AS constraints_extracted,
    (SELECT COUNT(*) FROM turn_extractions te
     JOIN conversation_turns ct ON ct.id = te.turn_id
     WHERE ct.session_id = s.id AND te.extraction_type = 'risk') AS risks_extracted,
    (SELECT COUNT(*) FROM extraction_conflicts ec
     WHERE ec.session_id = s.id AND ec.resolution_status = 'unresolved') AS unresolved_conflicts,
    s.started_at,
    s.completed_at,
    EXTRACT(EPOCH FROM (COALESCE(s.completed_at, NOW()) - s.started_at)) / 60 AS duration_minutes
FROM interrogation_sessions s;

COMMENT ON VIEW extraction_summary IS 'Summary of extractions from interrogation sessions';

-- -----------------------------------------------------------------------------
-- View: Feature Implementation Traceability
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW feature_implementation_trace AS
SELECT
    f.id AS feature_id,
    f.feature_id AS feature_code,
    f.name AS feature_name,
    f.priority,
    f.status AS feature_status,
    (
        SELECT jsonb_agg(jsonb_build_object(
            'journey_id', j.journey_id,
            'journey_name', j.name,
            'relationship', fjm.relationship_type,
            'step_count', (SELECT COUNT(*) FROM journey_steps_detailed WHERE journey_id = j.id)
        ))
        FROM feature_journey_mapping fjm
        JOIN user_journeys j ON j.id = fjm.journey_id
        WHERE fjm.feature_id = f.id
    ) AS journeys,
    (
        SELECT jsonb_agg(DISTINCT tc.component_type)
        FROM feature_journey_mapping fjm
        JOIN user_journeys j ON j.id = fjm.journey_id
        JOIN journey_steps_detailed js ON js.journey_id = j.id
        JOIN step_component_mapping scm ON scm.step_id = js.id
        JOIN technical_components tc ON tc.id = scm.component_id
        WHERE fjm.feature_id = f.id
    ) AS component_types,
    (
        SELECT jsonb_agg(DISTINCT js.db_tables_affected)
        FROM feature_journey_mapping fjm
        JOIN user_journeys j ON j.id = fjm.journey_id
        JOIN journey_steps_detailed js ON js.journey_id = j.id
        WHERE fjm.feature_id = f.id AND js.db_tables_affected IS NOT NULL
    ) AS database_tables,
    f.evidence_quote
FROM features f;

COMMENT ON VIEW feature_implementation_trace IS 'Traces features through journeys to implementation';

-- -----------------------------------------------------------------------------
-- View: Database Entity Usage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW entity_usage_summary AS
SELECT
    de.id AS entity_id,
    de.entity_name,
    de.table_name,
    (
        SELECT COUNT(DISTINCT js.journey_id)
        FROM journey_steps_detailed js
        WHERE de.table_name = ANY(js.db_tables_affected)
    ) AS journeys_using,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE de.table_name = ANY(db_tables_affected) AND db_operation = 'SELECT') AS select_count,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE de.table_name = ANY(db_tables_affected) AND db_operation = 'INSERT') AS insert_count,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE de.table_name = ANY(db_tables_affected) AND db_operation = 'UPDATE') AS update_count,
    (SELECT COUNT(*) FROM journey_steps_detailed WHERE de.table_name = ANY(db_tables_affected) AND db_operation = 'DELETE') AS delete_count,
    de.status
FROM database_entities de;

COMMENT ON VIEW entity_usage_summary IS 'Summary of how database entities are used across journeys';

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Function: Get complete journey trace (for debugging/documentation)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_journey_trace(p_journey_id UUID)
RETURNS TABLE (
    step_number INTEGER,
    step_name VARCHAR(255),
    layer_type VARCHAR(50),
    component_name VARCHAR(255),
    operation TEXT,
    entities_affected TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        js.step_number,
        js.step_name,
        'user'::VARCHAR(50) AS layer_type,
        js.ui_component_name AS component_name,
        js.user_action AS operation,
        NULL::TEXT AS entities_affected
    FROM journey_steps_detailed js
    WHERE js.journey_id = p_journey_id

    UNION ALL

    SELECT
        js.step_number,
        js.step_name,
        'api'::VARCHAR(50),
        js.api_operation_name,
        js.api_operation_type || ': ' || COALESCE(js.api_endpoint, 'N/A'),
        NULL
    FROM journey_steps_detailed js
    WHERE js.journey_id = p_journey_id AND js.api_operation_name IS NOT NULL

    UNION ALL

    SELECT
        js.step_number,
        js.step_name,
        'service'::VARCHAR(50),
        js.backend_service,
        js.backend_method,
        NULL
    FROM journey_steps_detailed js
    WHERE js.journey_id = p_journey_id AND js.backend_service IS NOT NULL

    UNION ALL

    SELECT
        js.step_number,
        js.step_name,
        'database'::VARCHAR(50),
        js.repository,
        js.db_operation,
        array_to_string(js.db_tables_affected, ', ')
    FROM journey_steps_detailed js
    WHERE js.journey_id = p_journey_id AND js.db_operation != 'NONE'

    ORDER BY step_number, layer_type;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_journey_trace IS 'Returns complete trace of a journey across all layers';

-- -----------------------------------------------------------------------------
-- Function: Link turn to extraction (with validation)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION link_turn_extraction(
    p_turn_id UUID,
    p_extraction_type VARCHAR(50),
    p_entity_type VARCHAR(100),
    p_entity_id UUID,
    p_verbatim_quote TEXT DEFAULT NULL,
    p_confidence FLOAT DEFAULT 1.0
) RETURNS UUID AS $$
DECLARE
    v_extraction_id UUID;
BEGIN
    INSERT INTO turn_extractions (
        turn_id, extraction_type, entity_type, entity_id,
        verbatim_quote, confidence
    ) VALUES (
        p_turn_id, p_extraction_type, p_entity_type, p_entity_id,
        p_verbatim_quote, p_confidence
    )
    RETURNING id INTO v_extraction_id;

    -- Update turn flags
    IF p_extraction_type = 'feature' THEN
        UPDATE conversation_turns SET contains_feature_info = TRUE WHERE id = p_turn_id;
    ELSIF p_extraction_type IN ('journey', 'journey_step') THEN
        UPDATE conversation_turns SET contains_journey_info = TRUE WHERE id = p_turn_id;
    ELSIF p_extraction_type = 'constraint' THEN
        UPDATE conversation_turns SET contains_constraint_info = TRUE WHERE id = p_turn_id;
    ELSIF p_extraction_type = 'decision' THEN
        UPDATE conversation_turns SET contains_decision = TRUE WHERE id = p_turn_id;
    END IF;

    RETURN v_extraction_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION link_turn_extraction IS 'Links a conversation turn to an extracted entity';

-- =============================================================================
-- FULL-TEXT SEARCH INDEXES (for production use)
-- =============================================================================
-- Uncomment if needed for searching conversation content
-- CREATE INDEX idx_conversation_turns_content_search
-- ON conversation_turns USING GIN (to_tsvector('english', content));

-- =============================================================================
-- SCHEMA VERSION TRACKING
-- =============================================================================
CREATE TABLE IF NOT EXISTS schema_versions (
    id SERIAL PRIMARY KEY,
    schema_name VARCHAR(100) NOT NULL,
    version VARCHAR(20) NOT NULL,
    applied_at TIMESTAMPTZ DEFAULT NOW(),
    description TEXT
);

INSERT INTO schema_versions (schema_name, version, description)
VALUES ('interview_schema', '1.0.0', 'Initial interview schema with 16 tables, 5 views, 2 functions')
ON CONFLICT DO NOTHING;
