SET search_path = crypto;

-- Key references (no raw keys stored; reference to KMS/secret manager identifier if needed)
CREATE TABLE IF NOT EXISTS key_refs (
  key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  provider TEXT NOT NULL CHECK (provider IN ('aws-kms','gcp-kms','azure-kv','vault','local')),
  ref TEXT NOT NULL, -- e.g., ARN, resource path, vault path
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  rotated_at TIMESTAMPTZ
);

COMMENT ON TABLE key_refs IS 'References to external KMS/Vault keys. No raw secrets stored in DB.';

-- Example helper functions to encrypt/decrypt using pgcrypto symmetric with app-supplied passphrase.
-- In production, prefer app-layer envelope encryption using a KMS; these are convenience methods.
CREATE OR REPLACE FUNCTION crypto.encrypt_text(value TEXT, passphrase TEXT)
RETURNS BYTEA
LANGUAGE SQL
AS $$
  SELECT pgp_sym_encrypt(value, passphrase, 'compress-algo=1, cipher-algo=aes256');
$$;

CREATE OR REPLACE FUNCTION crypto.decrypt_text(value BYTEA, passphrase TEXT)
RETURNS TEXT
LANGUAGE SQL
AS $$
  SELECT pgp_sym_decrypt(value, passphrase);
$$;

REVOKE ALL ON FUNCTION crypto.encrypt_text(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION crypto.decrypt_text(BYTEA, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION crypto.encrypt_text(TEXT, TEXT) TO app_role, app_admin;
GRANT EXECUTE ON FUNCTION crypto.decrypt_text(BYTEA, TEXT) TO app_admin; -- app_role should not generally decrypt PII
```
