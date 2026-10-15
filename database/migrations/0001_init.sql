-- 0001_init.sql - baseline schema for CacaoGrade AI
--
-- Activity 3, Part E ("PostgreSQL Persistence") asks for four resources:
--
--     users                  PK id; unique email; FK role_id -> roles.id
--     roles                  PK id
--     batches                PK id; FK farmer_id -> users.id
--     classification_records PK id; FK batch_id -> batches.id
--
-- The batch row and its first classification_records row are inserted in one
-- transaction; that rule lives in application code (database.py,
-- save_batch_with_record), not here, because no single-statement constraint
-- can span two tables.
--
-- `sessions` is the fifth table. It is not in the document's list, but the
-- JWT carries a `jti` that points at one of its rows, which turns the table
-- into a revocation list - logging out kills the bearer immediately instead of
-- leaving a token that stays valid until it expires.
--
-- Every statement is guarded with IF NOT EXISTS, so this file may be replayed
-- against an existing database. Apply it with:
--
--     psql "$DATABASE_URL" -f database/migrations/0001_init.sql
--
-- The running backend also creates these tables on startup (init_roles() ->
-- init_auth_db() -> init_db()); this file exists as the readable, versioned
-- statement of the schema.

BEGIN;

-- --------------------------------------------------------------- roles
-- Created first because `users.role_id` has to reference something.

CREATE TABLE IF NOT EXISTS roles (
    id                  SERIAL PRIMARY KEY,
    name                TEXT   NOT NULL UNIQUE,
    description         TEXT   NOT NULL,
    -- Part A's authorization model, carried on the row so a new environment
    -- cannot drift from what the API enforces.
    can_submit_photos   BOOLEAN NOT NULL DEFAULT FALSE,
    can_review_batches  BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO roles (name, description, can_submit_photos, can_review_batches)
VALUES
    ('farmer',           'Uploads cut-test photos for grading.',                          TRUE,  FALSE),
    ('staff',            'Cooperative staff who reviews and standardises batches.',       TRUE,  TRUE),
    ('buyer',            'Checks quality history before purchasing.',                     FALSE, FALSE),
    ('extension_worker', 'Agricultural extension worker monitoring multiple farmer accounts.', FALSE, TRUE),
    ('admin',            'Administrator who manages users and settings.',                 TRUE,  TRUE)
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------- users
-- `role` stays alongside `role_id`: the role *name* is what the JWT, the
-- endpoint guards and every response payload use, while `role_id` is the
-- referential integrity the document asks PostgreSQL to enforce.

CREATE TABLE IF NOT EXISTS users (
    id             SERIAL PRIMARY KEY,
    full_name      TEXT NOT NULL,
    email          TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    role           TEXT NOT NULL DEFAULT 'farmer',
    contact        TEXT    DEFAULT '',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    role_id        INTEGER REFERENCES roles(id)
);

-- -------------------------------------------------------------- sessions
-- One row per issued JWT. token is the `jti` claim.

CREATE TABLE IF NOT EXISTS sessions (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      TEXT    NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------------- batches
-- `farmer_id` is the owner column Activity 3 names.

CREATE TABLE IF NOT EXISTS batches (
    id         SERIAL PRIMARY KEY,
    farmer_id  INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    notes      TEXT    DEFAULT '',
    status     TEXT    DEFAULT 'Pending' NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------ classification_records
-- `batch_id` is nullable on purpose: a photo may be classified before anyone
-- groups it into a batch.

CREATE TABLE IF NOT EXISTS classification_records (
    id               SERIAL PRIMARY KEY,
    filename         TEXT NOT NULL,
    predicted_class  TEXT NOT NULL,
    confidence       REAL NOT NULL,
    recommendation   TEXT NOT NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id          INTEGER,
    batch_name       TEXT,
    notes            TEXT,
    quality_notes    TEXT,
    image_url        TEXT,
    engine           TEXT,
    batch_id         INTEGER REFERENCES batches(id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------- indexes
-- One index per column the list endpoints filter on.

CREATE INDEX IF NOT EXISTS idx_batches_farmer   ON batches (farmer_id);
CREATE INDEX IF NOT EXISTS idx_records_batch    ON classification_records (batch_id);
CREATE INDEX IF NOT EXISTS idx_records_user     ON classification_records (user_id);

COMMIT;
