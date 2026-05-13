-- ============================================
-- IoT-NAS — PostgreSQL Schema Initialization
-- ============================================
-- Auto-executed on first boot via docker-entrypoint-initdb.d
-- Database: iotnas

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- Core: IoT Events Table
-- ============================================
CREATE TABLE IF NOT EXISTS iot_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        VARCHAR(100) UNIQUE NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    priority        SMALLINT NOT NULL CHECK (priority BETWEEN 1 AND 4),
    device_id       VARCHAR(100),
    payload         JSONB DEFAULT '{}',
    timestamp_ns    BIGINT,
    device_trust    REAL CHECK (device_trust BETWEEN 0.0 AND 1.0),
    processed       BOOLEAN DEFAULT FALSE,
    storage_tier    VARCHAR(20) DEFAULT 'pending'
                    CHECK (storage_tier IN ('nvme', 'ceph', 's3', 'pending')),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_events_priority ON iot_events(priority);
CREATE INDEX IF NOT EXISTS idx_events_created ON iot_events(created_at);
CREATE INDEX IF NOT EXISTS idx_events_device ON iot_events(device_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON iot_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_processed ON iot_events(processed) WHERE processed = FALSE;
CREATE INDEX IF NOT EXISTS idx_events_payload ON iot_events USING GIN (payload);

-- ============================================
-- Device Registry
-- ============================================
CREATE TABLE IF NOT EXISTS device_registry (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       VARCHAR(100) UNIQUE NOT NULL,
    device_name     VARCHAR(200),
    device_type     VARCHAR(50) CHECK (device_type IN (
                        'camera', 'sensor', 'actuator', 'gateway',
                        'wearable', 'industrial', 'other'
                    )),
    trust_score     REAL DEFAULT 0.5 CHECK (trust_score BETWEEN 0.0 AND 1.0),
    is_active       BOOLEAN DEFAULT TRUE,
    last_seen       TIMESTAMPTZ,
    event_count     BIGINT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_active ON device_registry(is_active) WHERE is_active = TRUE;

-- ============================================
-- Forensic Audit Log (SQL mirror of hash chain)
-- ============================================
CREATE TABLE IF NOT EXISTS forensic_audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_index     INTEGER NOT NULL,
    event_id        VARCHAR(100) NOT NULL,
    event_type      VARCHAR(100),
    priority        SMALLINT,
    device          VARCHAR(100),
    payload         JSONB DEFAULT '{}',
    timestamp_us    BIGINT,
    prev_hash       VARCHAR(64) NOT NULL,
    hash            VARCHAR(64) NOT NULL,
    signature       TEXT NOT NULL,
    verify_key      VARCHAR(128),
    compliant       VARCHAR(50) DEFAULT 'ISO/IEC 27037',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forensic_chain ON forensic_audit_log(chain_index);
CREATE INDEX IF NOT EXISTS idx_forensic_hash ON forensic_audit_log(hash);

-- ============================================
-- Workflow Run Log (n8n workflow tracking)
-- ============================================
CREATE TABLE IF NOT EXISTS workflow_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name   VARCHAR(200) NOT NULL,
    event_id        VARCHAR(100),
    device_name     VARCHAR(200),
    status          VARCHAR(20) DEFAULT 'running'
                    CHECK (status IN ('running', 'completed', 'failed', 'skipped')),
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    duration_ms     INTEGER,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_workflow_status ON workflow_runs(status);

-- ============================================
-- Storage Quotas (per-device limits)
-- ============================================
CREATE TABLE IF NOT EXISTS device_quotas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       VARCHAR(100) UNIQUE NOT NULL REFERENCES device_registry(device_id),
    max_storage_mb  INTEGER DEFAULT 1024,
    used_storage_mb INTEGER DEFAULT 0,
    max_events_day  INTEGER DEFAULT 10000,
    used_events_day INTEGER DEFAULT 0,
    last_reset      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Alert History
-- ============================================
CREATE TABLE IF NOT EXISTS alert_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        VARCHAR(100),
    alert_type      VARCHAR(50) NOT NULL,
    priority        SMALLINT,
    channel         VARCHAR(50) CHECK (channel IN ('telegram', 'slack', 'sms', 'email')),
    sent            BOOLEAN DEFAULT FALSE,
    sent_at         TIMESTAMPTZ,
    retry_count     INTEGER DEFAULT 0,
    error_message   TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_sent ON alert_history(sent) WHERE sent = FALSE;

-- ============================================
-- Demo View: Priority Summary
-- ============================================
CREATE OR REPLACE VIEW priority_summary AS
SELECT
    priority,
    CASE priority
        WHEN 1 THEN 'P1-Emergency'
        WHEN 2 THEN 'P2-High'
        WHEN 3 THEN 'P3-Normal'
        WHEN 4 THEN 'P4-Batch'
    END AS level,
    COUNT(*) AS event_count,
    COUNT(*) FILTER (WHERE processed = TRUE) AS processed_count,
    COUNT(*) FILTER (WHERE processed = FALSE) AS pending_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (updated_at - created_at)) * 1000)::numeric, 1) AS avg_latency_ms
FROM iot_events
GROUP BY priority
ORDER BY priority;

-- ============================================
-- Demo View: Device Activity
-- ============================================
CREATE OR REPLACE VIEW device_activity AS
SELECT
    d.device_id,
    d.device_name,
    d.device_type,
    d.trust_score,
    d.is_active,
    d.last_seen,
    COUNT(e.id) AS total_events,
    COUNT(e.id) FILTER (WHERE e.priority = 1) AS p1_events,
    COUNT(e.id) FILTER (WHERE e.priority = 2) AS p2_events
FROM device_registry d
LEFT JOIN iot_events e ON d.device_id = e.device_id
GROUP BY d.device_id, d.device_name, d.device_type,
         d.trust_score, d.is_active, d.last_seen
ORDER BY total_events DESC;

-- ============================================
-- Function: Update timestamp on row change
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_updated
    BEFORE UPDATE ON iot_events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_device_updated
    BEFORE UPDATE ON device_registry
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================
-- Seed: Register demo devices
-- ============================================
INSERT INTO device_registry (device_id, device_name, device_type, trust_score)
VALUES
    ('camera_01', 'Entrance Camera', 'camera', 0.95),
    ('camera_02', 'Warehouse Camera', 'camera', 0.92),
    ('motor_01', 'Conveyor Motor A', 'industrial', 0.88),
    ('motor_02', 'Pump Motor B', 'industrial', 0.85),
    ('temp_01', 'Server Room Temp', 'sensor', 0.97),
    ('temp_02', 'Cold Storage Temp', 'sensor', 0.96),
    ('pressure_01', 'Boiler Pressure', 'sensor', 0.90),
    ('vibration_01', 'Turbine Vibration', 'sensor', 0.87),
    ('gateway_01', 'Edge Gateway North', 'gateway', 0.99),
    ('gateway_02', 'Edge Gateway South', 'gateway', 0.98),
    ('wearable_01', 'Worker Safety Band', 'wearable', 0.80),
    ('wearable_02', 'Supervisor HMD', 'wearable', 0.82)
ON CONFLICT (device_id) DO NOTHING;

-- Done
SELECT 'IoT-NAS schema initialized successfully' AS status;
