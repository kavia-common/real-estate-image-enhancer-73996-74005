-- Real Estate Image Enhancement Platform - PostgreSQL Schema
-- This schema supports:
-- - User accounts (with OAuth support readiness)
-- - Image metadata (before/after, batch uploads)
-- - Image edit requests and histories
-- - Subscription plans, subscriptions, usage tracking (trial and paid)
-- - Payment events (Stripe webhooks)
-- - API keys (server-side integration if needed)
-- - Audit and soft deletes

-- Enable useful extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ENUMS
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'plan_interval') THEN
        CREATE TYPE plan_interval AS ENUM ('day', 'week', 'month', 'year');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscription_status') THEN
        CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled', 'incomplete', 'incomplete_expired', 'unpaid');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'image_status') THEN
        CREATE TYPE image_status AS ENUM ('uploaded', 'processing', 'processed', 'failed', 'deleted');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'edit_status') THEN
        CREATE TYPE edit_status AS ENUM ('queued', 'in_progress', 'succeeded', 'failed');
    END IF;
END$$;

-- USERS
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           CITEXT UNIQUE NOT NULL,
    email_verified  TIMESTAMPTZ,
    password_hash   TEXT, -- nullable for SSO
    name            TEXT,
    role            TEXT DEFAULT 'user', -- can be 'user', 'admin'
    avatar_url      TEXT,
    provider        TEXT, -- e.g., 'password', 'google'
    provider_id     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_provider_id ON users (provider, provider_id);

-- SUBSCRIPTION PLANS (catalog)
CREATE TABLE IF NOT EXISTS subscription_plans (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_key            TEXT UNIQUE NOT NULL, -- e.g., 'trial_10', 'starter_50', 'pro_200'
    name                TEXT NOT NULL,
    description         TEXT,
    currency            TEXT NOT NULL DEFAULT 'usd',
    price_cents         INTEGER NOT NULL DEFAULT 0,
    interval            plan_interval NOT NULL DEFAULT 'month',
    interval_count      INTEGER NOT NULL DEFAULT 1,
    images_included     INTEGER NOT NULL, -- images per interval
    overage_price_cents INTEGER, -- optional overage per image
    stripe_price_id     TEXT, -- Stripe price id mapping
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- SUBSCRIPTIONS (per user)
CREATE TABLE IF NOT EXISTS subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id             UUID NOT NULL REFERENCES subscription_plans(id),
    status              subscription_status NOT NULL DEFAULT 'incomplete',
    start_date          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_end  TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    canceled_at         TIMESTAMPTZ,
    stripe_customer_id  TEXT,
    stripe_subscription_id TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_customer ON subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_sub ON subscriptions(stripe_subscription_id);

-- USAGE COUNTS (for trials and monthly usage)
CREATE TABLE IF NOT EXISTS usage_counters (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id     UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    period_start        TIMESTAMPTZ NOT NULL,
    period_end          TIMESTAMPTZ NOT NULL,
    images_allowed      INTEGER NOT NULL,
    images_used         INTEGER NOT NULL DEFAULT 0,
    last_reset_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_usage_period UNIQUE (user_id, period_start, period_end)
);

CREATE INDEX IF NOT EXISTS idx_usage_user_period ON usage_counters(user_id, period_start, period_end);

-- IMAGE BATCHES (for grouped uploads up to 30 images)
CREATE TABLE IF NOT EXISTS image_batches (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT,
    note            TEXT,
    total_images    INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_image_batches_user ON image_batches(user_id);

-- IMAGES
CREATE TABLE IF NOT EXISTS images (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    batch_id            UUID REFERENCES image_batches(id) ON DELETE SET NULL,
    original_url        TEXT NOT NULL, -- storage URL
    processed_url       TEXT,          -- after enhancement
    thumbnail_url       TEXT,
    width               INTEGER,
    height              INTEGER,
    format              TEXT, -- e.g., 'jpg','png','webp'
    status              image_status NOT NULL DEFAULT 'uploaded',
    error_message       TEXT,
    prompt              TEXT, -- last requested prompt
    labels              TEXT[], -- searchable tags (optional)
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb, -- arbitrary attributes
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_images_user ON images(user_id);
CREATE INDEX IF NOT EXISTS idx_images_batch ON images(batch_id);
CREATE INDEX IF NOT EXISTS idx_images_status ON images(status);
CREATE INDEX IF NOT EXISTS idx_images_labels_gin ON images USING GIN (labels);

-- EDIT REQUESTS (one per enhancement run)
CREATE TABLE IF NOT EXISTS edit_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    image_id            UUID NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prompt              TEXT NOT NULL, -- natural language edit prompt
    provider            TEXT NOT NULL DEFAULT 'google-nano-banana',
    provider_job_id     TEXT, -- job id from provider
    status              edit_status NOT NULL DEFAULT 'queued',
    request_payload     JSONB NOT NULL DEFAULT '{}'::jsonb, -- inputs sent to provider
    response_payload    JSONB NOT NULL DEFAULT '{}'::jsonb, -- full provider response
    error_message       TEXT,
    cost_cents          INTEGER, -- if you track cost per operation
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_edit_requests_image ON edit_requests(image_id);
CREATE INDEX IF NOT EXISTS idx_edit_requests_user ON edit_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_edit_requests_provider_job ON edit_requests(provider, provider_job_id);

-- EDIT HISTORY (versions of outputs per image)
CREATE TABLE IF NOT EXISTS edit_history (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    image_id            UUID NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    edit_request_id     UUID REFERENCES edit_requests(id) ON DELETE SET NULL,
    version_number      INTEGER NOT NULL, -- increment per image
    prompt              TEXT NOT NULL,
    before_url          TEXT NOT NULL,
    after_url           TEXT,
    diff_url            TEXT, -- optional diff image URL for before/after comparison
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_edit_history_version ON edit_history(image_id, version_number);

-- PAYMENT EVENTS (Stripe Webhooks)
CREATE TABLE IF NOT EXISTS payment_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id        TEXT UNIQUE NOT NULL, -- Stripe event id
    type            TEXT NOT NULL,
    payload         JSONB NOT NULL,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed       BOOLEAN NOT NULL DEFAULT FALSE,
    processed_at    TIMESTAMPTZ
);

-- API KEYS (optional for partner integrations or service-to-service auth)
CREATE TABLE IF NOT EXISTS api_keys (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    hashed_key      TEXT NOT NULL, -- store a hash of the API key
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_api_keys_user_name UNIQUE (user_id, name)
);

-- AUDIT LOG (generic)
CREATE TABLE IF NOT EXISTS audit_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    entity_type     TEXT NOT NULL, -- e.g., 'image','subscription','usage'
    entity_id       UUID,
    action          TEXT NOT NULL, -- e.g., 'create','update','delete','process'
    details         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TRIGGERS: updated_at automation
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'users_set_updated_at') THEN
        CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'subscription_plans_set_updated_at') THEN
        CREATE TRIGGER subscription_plans_set_updated_at BEFORE UPDATE ON subscription_plans
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'subscriptions_set_updated_at') THEN
        CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON subscriptions
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'usage_counters_set_updated_at') THEN
        CREATE TRIGGER usage_counters_set_updated_at BEFORE UPDATE ON usage_counters
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'images_set_updated_at') THEN
        CREATE TRIGGER images_set_updated_at BEFORE UPDATE ON images
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'edit_requests_set_updated_at') THEN
        CREATE TRIGGER edit_requests_set_updated_at BEFORE UPDATE ON edit_requests
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
END$$;

-- VIEW: simple current usage for each user
CREATE OR REPLACE VIEW v_user_current_usage AS
SELECT
    u.id AS user_id,
    u.email,
    uc.images_allowed,
    uc.images_used,
    GREATEST(uc.images_allowed - uc.images_used, 0) AS images_remaining,
    uc.period_start,
    uc.period_end
FROM users u
JOIN LATERAL (
    SELECT uc2.*
    FROM usage_counters uc2
    WHERE uc2.user_id = u.id
      AND uc2.period_start <= NOW() AND NOW() < uc2.period_end
    ORDER BY uc2.period_start DESC
    LIMIT 1
) uc ON TRUE;

-- Helpful function: get or create usage_counter for a period
CREATE OR REPLACE FUNCTION get_or_init_usage_counter(p_user_id UUID, p_period_start TIMESTAMPTZ, p_period_end TIMESTAMPTZ, p_images_allowed INT)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM usage_counters
    WHERE user_id = p_user_id AND period_start = p_period_start AND period_end = p_period_end;

    IF v_id IS NULL THEN
        INSERT INTO usage_counters (user_id, period_start, period_end, images_allowed, images_used)
        VALUES (p_user_id, p_period_start, p_period_end, p_images_allowed, 0)
        RETURNING id INTO v_id;
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment usage safely
CREATE OR REPLACE FUNCTION increment_image_usage(p_user_id UUID, p_amount INT)
RETURNS VOID AS $$
DECLARE
    rec RECORD;
BEGIN
    SELECT *
    INTO rec
    FROM v_user_current_usage
    WHERE user_id = p_user_id;

    IF rec IS NULL THEN
        RAISE EXCEPTION 'No active usage period for user %', p_user_id;
    END IF;

    UPDATE usage_counters
    SET images_used = images_used + p_amount,
        updated_at = NOW()
    WHERE user_id = p_user_id
      AND period_start = rec.period_start
      AND period_end = rec.period_end;

    -- Optional: enforce limit
    -- IF (rec.images_used + p_amount) > rec.images_allowed THEN
    --     RAISE EXCEPTION 'Usage exceeded for user %', p_user_id;
    -- END IF;
END;
$$ LANGUAGE plpgsql;
