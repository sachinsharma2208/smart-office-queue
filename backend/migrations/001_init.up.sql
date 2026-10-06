-- Smart Office Queue: initial schema (PostgreSQL 13+, uses gen_random_uuid()).

CREATE TABLE departments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(100) NOT NULL UNIQUE,
    code                    VARCHAR(10)  NOT NULL UNIQUE,      -- prefix used in token numbers (IT, HR, ...)
    sort_order              SMALLINT     NOT NULL DEFAULT 0,   -- display order in the apps
    is_paused               BOOLEAN      NOT NULL DEFAULT FALSE,
    last_token_seq          INTEGER      NOT NULL DEFAULT 0,   -- per-department counter -> IT-001, IT-002 ...
    default_service_minutes INTEGER      NOT NULL DEFAULT 5 CHECK (default_service_minutes > 0),
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(10)  NOT NULL CHECK (role IN ('STAFF', 'ADMIN')),
    department_id UUID REFERENCES departments(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- staff must belong to a department; admins may be department-less
    CONSTRAINT staff_requires_department CHECK (role = 'ADMIN' OR department_id IS NOT NULL)
);
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));
CREATE INDEX idx_users_department_id ON users (department_id);

CREATE TABLE tokens (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_number              VARCHAR(20) NOT NULL UNIQUE,
    department_id             UUID        NOT NULL REFERENCES departments(id),
    priority                  SMALLINT    NOT NULL DEFAULT 0 CHECK (priority IN (0, 1)),  -- 0 NORMAL, 1 PRIORITY
    status                    VARCHAR(12) NOT NULL DEFAULT 'WAITING'
                              CHECK (status IN ('WAITING','SERVING','COMPLETED','CANCELLED','TRANSFERRED')),
    no_show_count             SMALLINT    NOT NULL DEFAULT 0 CHECK (no_show_count >= 0),
    sequence_no               INTEGER     NOT NULL,                 -- numeric part of token_number (tie-breaker)
    queue_entered_at          TIMESTAMPTZ NOT NULL DEFAULT now(),   -- reset on first no-show => "end of queue"
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    called_at                 TIMESTAMPTZ,
    completed_at              TIMESTAMPTZ,
    cancelled_at              TIMESTAMPTZ,
    transferred_from_token_id UUID REFERENCES tokens(id)
);

-- Serves "next eligible token" and queue-position queries (matches ORDER BY priority DESC, queue_entered_at, sequence_no).
CREATE INDEX idx_tokens_queue_order ON tokens (department_id, status, priority DESC, queue_entered_at, sequence_no);
CREATE INDEX idx_tokens_department_id ON tokens (department_id);
CREATE INDEX idx_tokens_status ON tokens (status);
CREATE INDEX idx_tokens_priority ON tokens (priority);
CREATE INDEX idx_tokens_created_at ON tokens (created_at);
CREATE INDEX idx_tokens_transferred_from ON tokens (transferred_from_token_id) WHERE transferred_from_token_id IS NOT NULL;

-- Database-level guarantee: at most ONE serving token per department, even under concurrency.
CREATE UNIQUE INDEX uq_one_serving_per_department ON tokens (department_id) WHERE status = 'SERVING';

CREATE TABLE queue_events (
    id         BIGSERIAL PRIMARY KEY,
    token_id   UUID        NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    event_type VARCHAR(40) NOT NULL,
    metadata   JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_queue_events_token_id ON queue_events (token_id, created_at);
CREATE INDEX idx_queue_events_created_at ON queue_events (created_at);
