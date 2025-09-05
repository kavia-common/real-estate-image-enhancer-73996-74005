# Real Estate Images DB

PostgreSQL schema for the Real Estate Image Enhancement SaaS.

What it supports:
- Users (email/password or SSO-ready)
- Subscription plans + subscriptions
- Usage counters (trial and monthly)
- Image batches, images, edit requests, and edit history
- Payment events (Stripe webhook receipts)
- API keys (optional), audit logs
- Helpful views and functions for usage tracking

Quick start
1) Start local Postgres via the provided script:
   ./startup.sh

2) Apply schema and seed (startup.sh already tries to apply them if found):
   psql postgresql://appuser:dbuser123@localhost:5000/myapp -f schema.sql
   psql postgresql://appuser:dbuser123@localhost:5000/myapp -f seed.sql

Connection
- See db_connection.txt for a ready-to-use psql URL.
- db_visualizer/postgres.env contains environment variables for the included viewer.

Key tables
- users
- subscription_plans, subscriptions
- usage_counters
- image_batches, images
- edit_requests, edit_history
- payment_events
- api_keys, audit_logs

Views/Functions
- v_user_current_usage: current period usage per user
- get_or_init_usage_counter(user_id, period_start, period_end, images_allowed)
- increment_image_usage(user_id, amount)

Notes
- The schema is idempotent and safe to re-apply.
- Consider adding storage service and CDN integration for image URLs.
- Stripe ids (customer, subscription, price) are nullable; backend should populate them after checkout.

Environment variables (for visualizer)
- POSTGRES_URL, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT
