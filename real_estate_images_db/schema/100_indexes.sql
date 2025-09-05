-- Additional indexes
CREATE INDEX IF NOT EXISTS idx_images_checksum ON core.images(checksum);
CREATE INDEX IF NOT EXISTS idx_edit_requests_created ON core.edit_requests(created_at);
CREATE INDEX IF NOT EXISTS idx_usage_user_period ON core.usage_counters(user_id, period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_subscription_provider ON billing.subscriptions(provider, provider_subscription_id);
CREATE INDEX IF NOT EXISTS idx_payment_user_created ON billing.payment_events(user_id, created_at);
```
