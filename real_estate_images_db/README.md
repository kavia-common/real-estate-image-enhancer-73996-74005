# Real Estate Images DB

Secure PostgreSQL database for the Real Estate Image Enhancer platform.

What this contains:
- Role-based access control (RBAC) with separate roles for app, read-only, and admin
- Dedicated schemas:
  - core (users, images, edits, subscriptions, usage)
  - audit (audit logs, data access logs)
  - billing (plans, payments metadata)
  - config (feature flags, operational metadata)
  - crypto (encryption helpers / key refs)
- Column-level encryption using pgcrypto for selected fields (PII, secrets)
- Row-level timestamps, soft-deletes, and data retention hooks
- Audit triggers to capture data changes
- Backup/restore scripts already provided in container
- High-availability-ready design (primary keys, indexes, constraints)

Compliance intent:
- GDPR/CCPA: Data minimization, encryption, audit trail, soft delete with purge hooks
- PCI DSS: No raw card storage; store only Stripe IDs; encryption for tokens & secrets
- Security: Principle of least privilege; audit trails; tamper-evident logging

Files:
- schema/001_extensions.sql
- schema/010_roles.sql
- schema/020_schemas.sql
- schema/030_crypto.sql
- schema/040_core.sql
- schema/050_billing.sql
- schema/060_audit.sql
- schema/070_config.sql
- schema/080_rbac_grants.sql
- schema/090_triggers.sql
- schema/100_indexes.sql
- init_db.sh (idempotent bootstrap runner)
- .env.example (required env variables for init)

Usage:
1) Configure .env (see .env.example)
2) Run: ./init_db.sh
   - This connects to the target DB and executes SQL in order.

Connection note:
- This DB is for exclusive access by backend service. No direct frontend access.

Backups:
- backup_db.sh and restore_db.sh are included (universal scripts). For production,
  prefer pg_dump and point-in-time recovery with WAL archiving.

Retention:
- Soft deletes are supported using deleted_at fields; design includes data retention
  strategy to purge PII as required by GDPR/CCPA via scheduled process (implemented
  in backend ops; no cron in this container).
