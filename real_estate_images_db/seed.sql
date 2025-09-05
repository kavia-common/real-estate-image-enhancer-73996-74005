-- Seed data for Real Estate Image Enhancement Platform

-- Upsert helper for subscription_plans
INSERT INTO subscription_plans (plan_key, name, description, currency, price_cents, interval, interval_count, images_included, overage_price_cents, stripe_price_id, is_active)
VALUES
    ('trial_10', 'Free Trial (10 images)', 'Free trial with 10 image edits.', 'usd', 0, 'month', 1, 10, NULL, NULL, TRUE),
    ('starter_50', 'Starter 50', '50 images per month for small portfolios.', 'usd', 1900, 'month', 1, 50, 75, NULL, TRUE),
    ('pro_200', 'Pro 200', '200 images per month for growing agencies.', 'usd', 5900, 'month', 1, 200, 50, NULL, TRUE)
ON CONFLICT (plan_key) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    currency = EXCLUDED.currency,
    price_cents = EXCLUDED.price_cents,
    interval = EXCLUDED.interval,
    interval_count = EXCLUDED.interval_count,
    images_included = EXCLUDED.images_included,
    overage_price_cents = EXCLUDED.overage_price_cents,
    stripe_price_id = COALESCE(EXCLUDED.stripe_price_id, subscription_plans.stripe_price_id),
    is_active = EXCLUDED.is_active,
    updated_at = NOW();

-- Create a demo user
WITH upsert_user AS (
    INSERT INTO users (email, email_verified, password_hash, name, role, provider)
    VALUES ('demo@example.com', NOW(), '$2a$10$demoDevHashNotForProd', 'Demo Agent', 'user', 'password')
    ON CONFLICT (email) DO UPDATE SET
        name = EXCLUDED.name,
        role = EXCLUDED.role,
        updated_at = NOW()
    RETURNING id
), trial_plan AS (
    SELECT id AS plan_id FROM subscription_plans WHERE plan_key = 'trial_10'
)
INSERT INTO subscriptions (user_id, plan_id, status, start_date, current_period_start, current_period_end, cancel_at_period_end, metadata)
SELECT
    u.id, tp.plan_id, 'trialing',
    NOW(), date_trunc('month', NOW()), (date_trunc('month', NOW()) + INTERVAL '1 month'),
    TRUE, jsonb_build_object('source','seed')
FROM upsert_user u, trial_plan tp
ON CONFLICT DO NOTHING;

-- Initialize usage counter for current period for the demo user
WITH u AS (
    SELECT id FROM users WHERE email = 'demo@example.com'
), s AS (
    SELECT s.id AS subscription_id, sp.images_included
    FROM subscriptions s
    JOIN subscription_plans sp ON sp.id = s.plan_id
    JOIN users u2 ON u2.id = s.user_id
    WHERE u2.email = 'demo@example.com'
    ORDER BY s.created_at DESC
    LIMIT 1
)
SELECT get_or_init_usage_counter(
    (SELECT id FROM u),
    date_trunc('month', NOW()),
    (date_trunc('month', NOW()) + INTERVAL '1 month'),
    (SELECT images_included FROM s)
);

-- Create a demo image batch and images
WITH u AS (
    SELECT id AS user_id FROM users WHERE email = 'demo@example.com'
), batch AS (
    INSERT INTO image_batches (user_id, title, note, total_images)
    SELECT user_id, 'Demo Listing', 'Sample batch created by seed script', 2 FROM u
    RETURNING id, user_id
)
INSERT INTO images (user_id, batch_id, original_url, thumbnail_url, width, height, format, status, prompt, labels, metadata)
SELECT b.user_id, b.id,
       'https://example.com/images/demo-living-before.jpg',
       'https://example.com/images/demo-living-thumb.jpg',
       3000, 2000, 'jpg', 'uploaded',
       'Remove clutter, brighten room, add light staging', ARRAY['living room','staging','demo'],
       jsonb_build_object('address','123 Main St','mls','DEMO-123')
FROM batch b
UNION ALL
SELECT b.user_id, b.id,
       'https://example.com/images/demo-kitchen-before.jpg',
       'https://example.com/images/demo-kitchen-thumb.jpg',
       3000, 2000, 'jpg', 'uploaded',
       'Declutter countertops, enhance lighting, neutral tones', ARRAY['kitchen','staging','demo'],
       jsonb_build_object('address','123 Main St','mls','DEMO-123')
FROM batch b;

-- Create a demo edit request and history for the first image
WITH img AS (
    SELECT id, user_id, original_url FROM images ORDER BY created_at ASC LIMIT 1
), er AS (
    INSERT INTO edit_requests (image_id, user_id, prompt, provider, status, request_payload)
    SELECT id, user_id, 'Remove clutter, brighten room, add light staging', 'google-nano-banana', 'succeeded',
           jsonb_build_object('strength', 0.8, 'style', 'realistic')
    FROM img
    RETURNING id, image_id
)
INSERT INTO edit_history (image_id, edit_request_id, version_number, prompt, before_url, after_url, diff_url, notes)
SELECT e.image_id, e.id, 1,
       'Remove clutter, brighten room, add light staging',
       (SELECT original_url FROM img),
       'https://example.com/images/demo-living-after.jpg',
       NULL,
       'Initial enhancement completed (seed data)'
FROM er e;

-- Mark one image as processed with processed_url
UPDATE images
SET status = 'processed',
    processed_url = 'https://example.com/images/demo-living-after.jpg'
WHERE id IN (SELECT image_id FROM edit_history);

-- Increment usage by 1 for the processed image
WITH u AS (
    SELECT id AS user_id FROM users WHERE email = 'demo@example.com'
)
SELECT increment_image_usage((SELECT user_id FROM u), 1);
