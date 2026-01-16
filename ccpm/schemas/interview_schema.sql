-- =============================================================================
-- INTERVIEW SCHEMA - Hybrid 10-Table Design
-- =============================================================================
--
-- This schema stores interview/discovery data with:
--   - Simplified tables for features, pages, journeys, conversations
--   - Comprehensive journey_steps_detailed for full traceability
--   - Domain model capture (database_entities, technical_components)
--   - Integration credentials for third-party services
--
-- Tables:
--   1. feature                  - Product features discovered in interviews
--   2. page                     - UI pages/screens
--   3. journey                  - User journey headers
--   4. journey_steps_detailed   - Comprehensive step details (70+ columns)
--   5. conversation             - Interview transcripts
--   6. conversation_feature     - M:M conversation→feature link
--   7. database_entities        - Domain model tables being built
--   8. technical_components     - Services, resolvers, DTOs to build
--   9. step_component_mapping   - M:M steps↔components
--  10. integration_credentials  - Third-party service credentials
--
-- =============================================================================

-- Drop existing tables (both old and new schemas)
DROP TABLE IF EXISTS integration_credentials CASCADE;
DROP TABLE IF EXISTS entity_operations CASCADE;
DROP TABLE IF EXISTS trace_layers CASCADE;
DROP TABLE IF EXISTS backend_action_traces CASCADE;
DROP TABLE IF EXISTS step_component_mapping CASCADE;
DROP TABLE IF EXISTS database_entities CASCADE;
DROP TABLE IF EXISTS technical_components CASCADE;
DROP TABLE IF EXISTS feature_journey_mapping CASCADE;
DROP TABLE IF EXISTS step_dependencies CASCADE;
DROP TABLE IF EXISTS step_data_flow CASCADE;
DROP TABLE IF EXISTS journey_steps_detailed CASCADE;
DROP TABLE IF EXISTS user_journeys CASCADE;
DROP TABLE IF EXISTS extraction_conflicts CASCADE;
DROP TABLE IF EXISTS turn_extractions CASCADE;
DROP TABLE IF EXISTS conversation_turns CASCADE;
DROP TABLE IF EXISTS interrogation_sessions CASCADE;
DROP TABLE IF EXISTS features CASCADE;
DROP TABLE IF EXISTS functional_requirement CASCADE;
DROP TABLE IF EXISTS conversation_feature CASCADE;
DROP TABLE IF EXISTS conversation CASCADE;
DROP TABLE IF EXISTS journey_step CASCADE;
DROP TABLE IF EXISTS journey CASCADE;
DROP TABLE IF EXISTS page CASCADE;
DROP TABLE IF EXISTS feature CASCADE;

-- =============================================================================
-- TABLE 1: FEATURE
-- Product features discovered in interviews
-- =============================================================================
CREATE TABLE feature (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    functionality TEXT,
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN (
        'must_have', 'should_have', 'could_have', 'wont_have', 'high', 'medium', 'low'
    )),
    user_story TEXT,                          -- "As a X, I want Y, so that Z"
    acceptance_criteria JSONB DEFAULT '[]',   -- Array of criteria
    complexity VARCHAR(20) CHECK (complexity IN ('simple', 'moderate', 'complex')),
    effort_estimate VARCHAR(50),              -- "2 days", "1 sprint"
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE feature IS 'Product features discovered in interviews';
COMMENT ON COLUMN feature.priority IS 'MoSCoW priority or high/medium/low';
COMMENT ON COLUMN feature.acceptance_criteria IS 'JSONB array of acceptance criteria strings';

-- =============================================================================
-- TABLE 2: PAGE
-- UI pages/screens in the application
-- =============================================================================
CREATE TABLE page (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    title VARCHAR(500),
    route VARCHAR(255),                       -- /invoices/new
    page_type VARCHAR(50) CHECK (page_type IN (
        'form', 'dashboard', 'list', 'detail', 'modal', 'wizard', 'settings', 'other'
    )),
    description TEXT,
    layout_notes TEXT,                        -- Layout/wireframe notes
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE page IS 'UI pages/screens in the application';
COMMENT ON COLUMN page.route IS 'URL route pattern, e.g., /invoices/:id';

-- =============================================================================
-- TABLE 3: JOURNEY
-- User journey headers (actor, goal, trigger)
-- =============================================================================
CREATE TABLE journey (
    id SERIAL PRIMARY KEY,
    feature_id INTEGER REFERENCES feature(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    actor VARCHAR(100),                       -- "AP Clerk", "Manager"
    actor_description TEXT,                   -- Detailed actor context
    trigger_event TEXT,                       -- "User clicks Create Invoice"
    goal TEXT,                                -- "Invoice submitted for approval"
    preconditions TEXT,                       -- What must be true before starting
    postconditions TEXT,                      -- What is true after completion
    success_criteria JSONB DEFAULT '[]',      -- Array of success criteria
    exception_paths JSONB DEFAULT '[]',       -- Alternative/error paths
    frequency VARCHAR(50) CHECK (frequency IN (
        'multiple_daily', 'daily', 'weekly', 'monthly', 'occasional', 'rare'
    )),
    complexity VARCHAR(20) CHECK (complexity IN ('simple', 'moderate', 'complex')),
    estimated_duration VARCHAR(50),           -- "2 minutes", "30 seconds"
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'validated', 'approved')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE journey IS 'User journey headers defining actor, goal, and context';
COMMENT ON COLUMN journey.actor IS 'User role performing this journey, e.g., AP Clerk';
COMMENT ON COLUMN journey.trigger_event IS 'Event that starts this journey';

-- =============================================================================
-- TABLE 4: JOURNEY_STEPS_DETAILED
-- Comprehensive step details with full layer traceability
-- =============================================================================
CREATE TABLE journey_steps_detailed (
    id SERIAL PRIMARY KEY,
    journey_id INTEGER NOT NULL REFERENCES journey(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    step_name VARCHAR(255) NOT NULL,
    step_description TEXT,

    -- USER LAYER
    user_action TEXT NOT NULL,                -- "Fill invoice amount"
    user_intent TEXT,                         -- Why user performs this action
    user_decision_point BOOLEAN DEFAULT FALSE,
    decision_options JSONB,                   -- Options if decision point

    -- UI LAYER
    page_id INTEGER REFERENCES page(id) ON DELETE SET NULL,
    ui_component_type VARCHAR(100),           -- "form", "button", "modal"
    ui_component_name VARCHAR(255),           -- "InvoiceForm", "SubmitButton"
    ui_component_location TEXT,               -- Where on the page
    ui_page_route VARCHAR(500),               -- /invoices/new
    ui_state_before JSONB,                    -- UI state before action
    ui_state_after JSONB,                     -- UI state after action
    ui_validation_rules JSONB,                -- Client-side validation
    ui_feedback TEXT,                         -- Success/error messages shown

    -- FRONTEND EVENT LAYER
    frontend_event_type VARCHAR(100),         -- "click", "submit", "change"
    frontend_event_name VARCHAR(255),         -- "onInvoiceSubmit"
    frontend_event_payload JSONB,             -- Data sent with event
    frontend_state_change JSONB,              -- Redux/state changes

    -- API LAYER
    api_protocol VARCHAR(50) DEFAULT 'graphql' CHECK (api_protocol IN (
        'graphql', 'rest', 'grpc', 'websocket'
    )),
    api_operation_type VARCHAR(50),           -- "mutation", "query", "POST"
    api_operation_name VARCHAR(255),          -- "createInvoice"
    api_endpoint VARCHAR(500),                -- /api/invoices or null for GraphQL
    api_request_schema JSONB,                 -- Request payload structure
    api_response_schema JSONB,                -- Response structure
    api_headers JSONB,                        -- Required headers
    api_auth_required BOOLEAN DEFAULT TRUE,
    api_rate_limited BOOLEAN DEFAULT FALSE,

    -- BACKEND SERVICE LAYER
    backend_resolver VARCHAR(255),            -- GraphQL resolver name
    backend_service VARCHAR(255),             -- Service class name
    backend_method VARCHAR(255),              -- Method name
    backend_input_dto VARCHAR(255),           -- Input DTO class
    backend_output_dto VARCHAR(255),          -- Output DTO class

    -- BUSINESS LOGIC LAYER
    business_rules JSONB,                     -- Business rules applied
    validation_rules JSONB,                   -- Server-side validation
    transformation_logic TEXT,                -- Data transformations
    side_effects JSONB,                       -- Side effects triggered

    -- DATA ACCESS LAYER
    repository VARCHAR(255),                  -- Repository class
    repository_method VARCHAR(255),           -- Repository method

    -- DATABASE LAYER
    db_operation VARCHAR(50) CHECK (db_operation IN (
        'create', 'read', 'update', 'delete', 'upsert', 'batch'
    )),
    db_tables_affected JSONB,                 -- Tables touched
    db_entities_affected JSONB,               -- Entity types affected
    db_fields_read JSONB,                     -- Fields read
    db_fields_written JSONB,                  -- Fields written
    db_transaction_required BOOLEAN DEFAULT FALSE,
    db_isolation_level VARCHAR(50),           -- Transaction isolation

    -- RESPONSE FLOW
    response_to_frontend JSONB,               -- What's sent back to UI
    ui_update_triggered TEXT,                 -- UI updates after response
    next_step_condition TEXT,                 -- Condition for next step

    -- ERROR HANDLING
    possible_errors JSONB,                    -- Error scenarios
    error_ui_display TEXT,                    -- How errors shown to user
    rollback_behavior TEXT,                   -- Rollback on failure

    -- ASYNC/BACKGROUND
    is_async BOOLEAN DEFAULT FALSE,
    background_job_type VARCHAR(100),         -- Job queue type
    polling_required BOOLEAN DEFAULT FALSE,
    webhook_triggered BOOLEAN DEFAULT FALSE,

    -- METADATA
    estimated_duration_ms INTEGER,            -- Expected duration
    is_optional BOOLEAN DEFAULT FALSE,
    is_automated BOOLEAN DEFAULT FALSE,       -- System-triggered step
    requires_confirmation BOOLEAN DEFAULT FALSE,
    notes TEXT,                               -- Additional notes
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (journey_id, step_number),
    CONSTRAINT positive_step_number CHECK (step_number > 0)
);

COMMENT ON TABLE journey_steps_detailed IS 'Comprehensive journey step details with full layer traceability';
COMMENT ON COLUMN journey_steps_detailed.step_number IS 'Order within journey (1, 2, 3...)';
COMMENT ON COLUMN journey_steps_detailed.user_action IS 'What the user does at this step';

-- =============================================================================
-- TABLE 5: CONVERSATION
-- Interview transcripts with flexible JSONB metadata
-- =============================================================================
CREATE TABLE conversation (
    id SERIAL PRIMARY KEY,
    session_name VARCHAR(255),
    transcript TEXT,
    status VARCHAR(20) DEFAULT 'in_progress' CHECK (status IN (
        'in_progress', 'paused', 'complete', 'abandoned'
    )),
    session_type VARCHAR(50) CHECK (session_type IN (
        'discovery', 'feature', 'journey', 'technical', 'research', 'other'
    )),
    domain VARCHAR(50) CHECK (domain IN (
        'technical', 'business', 'creative', 'research', 'operational'
    )),
    total_turns INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',              -- Flexible for interview context
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE conversation IS 'Interview transcripts with flexible metadata';
COMMENT ON COLUMN conversation.metadata IS 'JSONB for flexible data: turns, context, decisions';

-- =============================================================================
-- TABLE 6: CONVERSATION_FEATURE
-- M:M link: which conversations discovered which features
-- =============================================================================
CREATE TABLE conversation_feature (
    conversation_id INTEGER NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    feature_id INTEGER NOT NULL REFERENCES feature(id) ON DELETE CASCADE,
    discovery_context TEXT,                   -- Quote or context where feature mentioned
    verbatim_quote TEXT,                      -- Exact quote from conversation
    confidence VARCHAR(20) CHECK (confidence IN ('high', 'medium', 'low')),
    validated BOOLEAN DEFAULT FALSE,
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (conversation_id, feature_id)
);

COMMENT ON TABLE conversation_feature IS 'M:M: conversations discover features';
COMMENT ON COLUMN conversation_feature.discovery_context IS 'Context from conversation';
COMMENT ON COLUMN conversation_feature.verbatim_quote IS 'Exact quote where feature was mentioned';

-- =============================================================================
-- TABLE 7: DATABASE_ENTITIES
-- Domain model tables being built for the new application
-- =============================================================================
CREATE TABLE database_entities (
    id SERIAL PRIMARY KEY,
    entity_name VARCHAR(255) NOT NULL UNIQUE,
    table_name VARCHAR(255),                  -- Actual DB table name
    description TEXT,
    schema_definition JSONB,                  -- Column definitions
    primary_key VARCHAR(255),                 -- PK column(s)
    indexes JSONB DEFAULT '[]',               -- Index definitions
    constraints JSONB DEFAULT '[]',           -- Constraint definitions
    relationships JSONB DEFAULT '[]',         -- FK relationships
    sample_data JSONB,                        -- Example records
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN (
        'planned', 'designed', 'implemented', 'migrated'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE database_entities IS 'Domain model tables being built for the new application';
COMMENT ON COLUMN database_entities.schema_definition IS 'JSONB defining columns: [{name, type, nullable, default}]';
COMMENT ON COLUMN database_entities.relationships IS 'FK relationships to other entities';

-- =============================================================================
-- TABLE 8: TECHNICAL_COMPONENTS
-- Services, resolvers, DTOs, and other technical components to build
-- =============================================================================
CREATE TABLE technical_components (
    id SERIAL PRIMARY KEY,
    component_type VARCHAR(50) NOT NULL CHECK (component_type IN (
        'api_resolver', 'service', 'repository', 'dto', 'entity',
        'ui_component', 'ui_page', 'middleware', 'utility', 'config', 'other'
    )),
    component_name VARCHAR(255) NOT NULL,
    component_path TEXT,                      -- File path where implemented
    description TEXT,
    specifications JSONB DEFAULT '{}',        -- Detailed specs
    interface_definition TEXT,                -- Interface/type definition
    depends_on_ids INTEGER[],                 -- IDs of dependent components
    related_entity_ids INTEGER[],             -- Related database_entities
    status VARCHAR(20) DEFAULT 'planned' CHECK (status IN (
        'planned', 'designed', 'implemented', 'tested'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (component_type, component_name)
);

COMMENT ON TABLE technical_components IS 'Technical components to build: services, resolvers, DTOs';
COMMENT ON COLUMN technical_components.component_path IS 'File path, e.g., src/services/InvoiceService.ts';
COMMENT ON COLUMN technical_components.specifications IS 'JSONB for methods, parameters, return types';

-- =============================================================================
-- TABLE 9: STEP_COMPONENT_MAPPING
-- M:M link between journey steps and technical components
-- =============================================================================
CREATE TABLE step_component_mapping (
    id SERIAL PRIMARY KEY,
    step_id INTEGER NOT NULL REFERENCES journey_steps_detailed(id) ON DELETE CASCADE,
    component_id INTEGER NOT NULL REFERENCES technical_components(id) ON DELETE CASCADE,
    usage_type VARCHAR(50) NOT NULL CHECK (usage_type IN (
        'invokes', 'reads', 'writes', 'validates', 'transforms', 'renders'
    )),
    usage_order INTEGER DEFAULT 1,            -- Order of usage within step
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (step_id, component_id, usage_type)
);

COMMENT ON TABLE step_component_mapping IS 'M:M: which components are used in which steps';
COMMENT ON COLUMN step_component_mapping.usage_type IS 'How the component is used in this step';

-- =============================================================================
-- TABLE 10: INTEGRATION_CREDENTIALS
-- Third-party service credentials for integrations
-- =============================================================================
-- SECURITY NOTE: All password/secret fields store encrypted values.
-- Encryption/decryption is handled at the application layer using AES-256.
-- The encryption key should be stored in environment variables or a secrets manager.
-- =============================================================================
CREATE TABLE integration_credentials (
    id SERIAL PRIMARY KEY,

    -- Integration identification
    integration_type VARCHAR(50) NOT NULL,    -- 'quickbooks', 'shopify', 'stripe', 'twilio', etc.
    integration_name VARCHAR(255),             -- Human-readable name, e.g., "QuickBooks Production"
    purpose TEXT,                              -- What this integration is used for, e.g., "accounting and invoicing"
    environment VARCHAR(20) DEFAULT 'production' CHECK (environment IN (
        'sandbox', 'development', 'staging', 'production'
    )),

    -- Website/endpoint information
    base_url VARCHAR(500),                     -- API base URL
    login_url VARCHAR(500),                    -- Web login URL for SSO/OAuth
    webhook_url VARCHAR(500),                  -- Incoming webhook endpoint
    webhook_secret_encrypted TEXT,             -- Encrypted webhook signing secret

    -- Basic authentication
    username VARCHAR(255),                     -- Username or email
    password_encrypted TEXT,                   -- AES-256 encrypted password

    -- API key authentication
    api_key_encrypted TEXT,                    -- Encrypted API key
    api_secret_encrypted TEXT,                 -- Encrypted API secret (if paired key)

    -- OAuth 2.0 credentials
    oauth_client_id VARCHAR(255),              -- OAuth client/application ID
    oauth_client_secret_encrypted TEXT,        -- Encrypted client secret
    oauth_access_token_encrypted TEXT,         -- Encrypted access token
    oauth_refresh_token_encrypted TEXT,        -- Encrypted refresh token
    oauth_token_type VARCHAR(50) DEFAULT 'Bearer',
    oauth_token_expires_at TIMESTAMPTZ,        -- When access token expires
    oauth_scopes TEXT[],                       -- Granted scopes
    oauth_authorization_url VARCHAR(500),      -- OAuth authorization endpoint
    oauth_token_url VARCHAR(500),              -- OAuth token endpoint

    -- Additional secrets (flexible key-value store)
    -- Use for: merchant_id, store_id, account_id, custom tokens, etc.
    additional_secrets JSONB DEFAULT '{}',     -- Encrypted JSONB blob

    -- Credential status and validation
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending',      -- Not yet validated
        'active',       -- Validated and working
        'expired',      -- Token/password expired
        'revoked',      -- Manually or programmatically revoked
        'error',        -- Validation failed
        'deferred'      -- User skipped, to be provided later
    )),
    last_validated_at TIMESTAMPTZ,             -- Last successful validation
    last_used_at TIMESTAMPTZ,                  -- Last API call using these credentials
    validation_error TEXT,                     -- Error message from last validation attempt

    -- Metadata and audit
    scope_name VARCHAR(100),                   -- Link to scope/project if applicable
    notes TEXT,                                -- User notes about this integration
    created_by VARCHAR(100),                   -- Who created this credential
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Prevent duplicate credentials for same integration/environment
    UNIQUE (integration_type, environment, scope_name)
);

COMMENT ON TABLE integration_credentials IS 'Third-party service credentials (encrypted at rest)';
COMMENT ON COLUMN integration_credentials.integration_type IS 'Service type: quickbooks, shopify, stripe, twilio, sendgrid, etc.';
COMMENT ON COLUMN integration_credentials.purpose IS 'What this integration is used for, extracted from conversation';
COMMENT ON COLUMN integration_credentials.environment IS 'Environment: sandbox for testing, production for live';
COMMENT ON COLUMN integration_credentials.password_encrypted IS 'AES-256 encrypted - decrypt in application layer';
COMMENT ON COLUMN integration_credentials.additional_secrets IS 'Encrypted JSONB for custom fields: {merchant_id, store_id, custom_token, etc.}';
COMMENT ON COLUMN integration_credentials.status IS 'Current status: pending, active, expired, revoked, error, deferred';
COMMENT ON COLUMN integration_credentials.scope_name IS 'Links to .claude/scopes/{scope_name}/ if applicable';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Feature indexes
CREATE INDEX idx_feature_priority ON feature(priority);
CREATE INDEX idx_feature_name ON feature(name);

-- Page indexes
CREATE INDEX idx_page_route ON page(route);
CREATE INDEX idx_page_type ON page(page_type);

-- Journey indexes
CREATE INDEX idx_journey_feature ON journey(feature_id);
CREATE INDEX idx_journey_actor ON journey(actor);
CREATE INDEX idx_journey_status ON journey(status);

-- Journey steps indexes (critical for queries)
CREATE INDEX idx_steps_journey ON journey_steps_detailed(journey_id);
CREATE INDEX idx_steps_page ON journey_steps_detailed(page_id);
CREATE INDEX idx_steps_order ON journey_steps_detailed(journey_id, step_number);
CREATE INDEX idx_steps_api_operation ON journey_steps_detailed(api_operation_name);
CREATE INDEX idx_steps_backend_service ON journey_steps_detailed(backend_service);
CREATE INDEX idx_steps_db_operation ON journey_steps_detailed(db_operation);

-- Conversation indexes
CREATE INDEX idx_conversation_session ON conversation(session_name);
CREATE INDEX idx_conversation_status ON conversation(status);
CREATE INDEX idx_conversation_metadata ON conversation USING GIN (metadata);

-- Conversation-feature junction indexes
CREATE INDEX idx_conv_feature_conv ON conversation_feature(conversation_id);
CREATE INDEX idx_conv_feature_feat ON conversation_feature(feature_id);

-- Database entities indexes
CREATE INDEX idx_db_entity_name ON database_entities(entity_name);
CREATE INDEX idx_db_entity_status ON database_entities(status);

-- Technical components indexes
CREATE INDEX idx_component_type ON technical_components(component_type);
CREATE INDEX idx_component_name ON technical_components(component_name);
CREATE INDEX idx_component_status ON technical_components(status);

-- Step-component mapping indexes
CREATE INDEX idx_step_comp_step ON step_component_mapping(step_id);
CREATE INDEX idx_step_comp_comp ON step_component_mapping(component_id);

-- Integration credentials indexes
CREATE INDEX idx_creds_type ON integration_credentials(integration_type);
CREATE INDEX idx_creds_env ON integration_credentials(environment);
CREATE INDEX idx_creds_status ON integration_credentials(status);
CREATE INDEX idx_creds_scope ON integration_credentials(scope_name);
CREATE INDEX idx_creds_type_env ON integration_credentials(integration_type, environment);
CREATE INDEX idx_creds_oauth_expires ON integration_credentials(oauth_token_expires_at)
    WHERE oauth_token_expires_at IS NOT NULL;

-- =============================================================================
-- VIEWS
-- =============================================================================

-- View: Complete journey with all steps
CREATE OR REPLACE VIEW journey_full_view AS
SELECT
    j.id AS journey_id,
    j.name AS journey_name,
    j.actor,
    j.trigger_event,
    j.goal,
    j.frequency,
    j.priority,
    f.id AS feature_id,
    f.name AS feature_name,
    js.step_number,
    js.step_name,
    js.user_action,
    js.ui_component_name,
    js.api_operation_name,
    js.backend_service,
    js.db_operation,
    p.id AS page_id,
    p.name AS page_name,
    p.route AS page_route
FROM journey j
LEFT JOIN feature f ON j.feature_id = f.id
LEFT JOIN journey_steps_detailed js ON j.id = js.journey_id
LEFT JOIN page p ON js.page_id = p.id
ORDER BY j.id, js.step_number;

COMMENT ON VIEW journey_full_view IS 'Complete journey with all steps and related entities';

-- View: Feature discovery traceability
CREATE OR REPLACE VIEW feature_discovery_view AS
SELECT
    f.id AS feature_id,
    f.name AS feature_name,
    f.priority,
    f.complexity,
    c.id AS conversation_id,
    c.session_name,
    cf.discovery_context,
    cf.verbatim_quote,
    cf.confidence,
    cf.discovered_at
FROM feature f
LEFT JOIN conversation_feature cf ON f.id = cf.feature_id
LEFT JOIN conversation c ON cf.conversation_id = c.id
ORDER BY f.id, cf.discovered_at;

COMMENT ON VIEW feature_discovery_view IS 'Trace which conversations discovered which features';

-- View: Step technical components
CREATE OR REPLACE VIEW step_components_view AS
SELECT
    js.id AS step_id,
    js.journey_id,
    js.step_number,
    js.step_name,
    js.user_action,
    tc.id AS component_id,
    tc.component_type,
    tc.component_name,
    tc.component_path,
    scm.usage_type,
    scm.usage_order
FROM journey_steps_detailed js
LEFT JOIN step_component_mapping scm ON js.id = scm.step_id
LEFT JOIN technical_components tc ON scm.component_id = tc.id
ORDER BY js.journey_id, js.step_number, scm.usage_order;

COMMENT ON VIEW step_components_view IS 'Steps with their technical components';

-- View: Database entity usage
CREATE OR REPLACE VIEW entity_usage_view AS
SELECT
    de.id AS entity_id,
    de.entity_name,
    de.table_name,
    de.status AS entity_status,
    js.id AS step_id,
    js.journey_id,
    js.step_number,
    js.step_name,
    js.db_operation,
    j.name AS journey_name
FROM database_entities de
LEFT JOIN journey_steps_detailed js ON js.db_entities_affected ? de.entity_name
LEFT JOIN journey j ON js.journey_id = j.id
ORDER BY de.entity_name, j.id, js.step_number;

COMMENT ON VIEW entity_usage_view IS 'Which steps affect which database entities';

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function: Get all steps for a journey with component info
CREATE OR REPLACE FUNCTION get_journey_steps_full(p_journey_id INTEGER)
RETURNS TABLE (
    step_number INTEGER,
    step_name VARCHAR(255),
    user_action TEXT,
    ui_component_name VARCHAR(255),
    api_operation_name VARCHAR(255),
    backend_service VARCHAR(255),
    db_operation VARCHAR(50),
    page_name VARCHAR(255),
    page_route VARCHAR(255),
    components JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        js.step_number,
        js.step_name,
        js.user_action,
        js.ui_component_name,
        js.api_operation_name,
        js.backend_service,
        js.db_operation,
        p.name,
        p.route,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'type', tc.component_type,
                    'name', tc.component_name,
                    'usage', scm.usage_type
                )
            ) FILTER (WHERE tc.id IS NOT NULL),
            '[]'::jsonb
        ) AS components
    FROM journey_steps_detailed js
    LEFT JOIN page p ON js.page_id = p.id
    LEFT JOIN step_component_mapping scm ON js.id = scm.step_id
    LEFT JOIN technical_components tc ON scm.component_id = tc.id
    WHERE js.journey_id = p_journey_id
    GROUP BY js.step_number, js.step_name, js.user_action, js.ui_component_name,
             js.api_operation_name, js.backend_service, js.db_operation, p.name, p.route
    ORDER BY js.step_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_journey_steps_full IS 'Get all steps for a journey with component info';

-- Function: Link conversation to feature
CREATE OR REPLACE FUNCTION link_conversation_feature(
    p_conversation_id INTEGER,
    p_feature_id INTEGER,
    p_context TEXT DEFAULT NULL,
    p_quote TEXT DEFAULT NULL,
    p_confidence VARCHAR(20) DEFAULT 'medium'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO conversation_feature (conversation_id, feature_id, discovery_context, verbatim_quote, confidence)
    VALUES (p_conversation_id, p_feature_id, p_context, p_quote, p_confidence)
    ON CONFLICT (conversation_id, feature_id) DO UPDATE
    SET discovery_context = COALESCE(EXCLUDED.discovery_context, conversation_feature.discovery_context),
        verbatim_quote = COALESCE(EXCLUDED.verbatim_quote, conversation_feature.verbatim_quote),
        confidence = EXCLUDED.confidence;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION link_conversation_feature IS 'Link a conversation to a discovered feature';

-- =============================================================================
-- SCHEMA VERSION
-- =============================================================================
COMMENT ON SCHEMA public IS 'Interview Schema v3.1.0 - Hybrid 10-table design with comprehensive step tracing and integration credentials';
