SET search_path = billing, public;

-- Subscription plans
CREATE TABLE IF NOT EXISTS plans (
  plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code TEXT NOT NULL UNIQUE, -- e.g., 'FREE_TRIAL','PRO_50','PRO_200'
  name TEXT NOT NULL,
  images_per_month INT NOT NULL CHECK (images_per_month >= 0),
  price_cents INT NOT NULL CHECK (price_cents >= 0),
  currency TEXT NOT NULL DEFAULT 'usd',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Subscriptions
CREATE TABLE IF NOT EXISTS subscriptions (
  subscription_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES plans(plan_id) ON DELETE RESTRICT,
  provider TEXT NOT NULL DEFAULT 'stripe',
  provider_subscription_id TEXT, -- e.g., Stripe subscription ID
  status TEXT NOT NULL CHECK (status IN ('incomplete','trialing','active','past_due','canceled','unpaid')),
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  canceled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

-- Payment events (no card data stored)
CREATE TABLE IF NOT EXISTS payment_events (
  event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'stripe',
  provider_event_id TEXT NOT NULL, -- e.g., Stripe event ID
  type TEXT NOT NULL, -- invoice.paid, charge.succeeded, etc.
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```
