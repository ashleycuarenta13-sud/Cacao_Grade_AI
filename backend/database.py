import os
from urllib.parse import unquote, urlparse

from envfile import load_env

# Part F keeps settings in a gitignored `.env`, so it has to be read before any
# of the environment lookups below run.
load_env()

import psycopg2


# Activity 3, Part F keeps every secret and endpoint in a gitignored `.env`:
#
#     API_BASE_URL, DATABASE_URL, JWT_SECRET, CLOUD_STORAGE_BUCKET,
#     CNN_SERVICE_URL
#
# `DATABASE_URL` is the one this module needs. The values below are the local
# coursework defaults, so a checkout with no `.env` at all still runs, while a
# deployed instance only has to supply the one variable.
DEFAULT_DATABASE_URL = "postgresql://postgres:admin123@localhost:5432/cacao_gradeai"


def _split_database_url(url: str) -> dict:
    """Turns a connection URL into the kwargs psycopg2.connect() expects."""
    parsed = urlparse(url)

    config = {
        "host": parsed.hostname or "localhost",
        "port": parsed.port or 5432,
        "database": (parsed.path or "/").lstrip("/") or "postgres",
        "user": unquote(parsed.username or "postgres"),
        "password": unquote(parsed.password or ""),
    }

    if parsed.query:
        # `?sslmode=require` and friends are still plain psycopg2 options.
        from urllib.parse import parse_qsl

        config.update(dict(parse_qsl(parsed.query)))

    return config


def _database_config() -> dict:
    url = (
        os.getenv("CACAO_DATABASE_URL")
        or os.getenv("DATABASE_URL")
        or DEFAULT_DATABASE_URL
    )

    # Individual variables win over the URL, so a container can override one
    # field without having to rebuild the whole connection string.
    config = _split_database_url(url)

    for key, env in (
        ("host", "CACAO_DB_HOST"),
        ("port", "CACAO_DB_PORT"),
        ("database", "CACAO_DB_NAME"),
        ("user", "CACAO_DB_USER"),
        ("password", "CACAO_DB_PASSWORD"),
    ):
        value = os.getenv(env)

        if value:
            config[key] = int(value) if key == "port" else value

    return config


DB_CONFIG = _database_config()

# Part A - "Actors / user roles". The registry keeps the five documented
# actors in one place and records what each of them is allowed to do.
ROLES = [
    ("farmer", "Uploads cut-test photos for grading.", True, False),
    ("staff", "Cooperative staff who reviews and standardises batches.", True, True),
    ("buyer", "Checks quality history before purchasing.", False, False),
    ("extension_worker", "Agricultural extension worker monitoring multiple farmer accounts.", False, True),
    ("admin", "Administrator who manages users and settings.", True, True),
]

# Fermentation stages, in cut-test order.
STAGES = ["unfermented", "partially_fermented", "well_fermented", "over_fermented"]

_BATCH_SELECT = """
    SELECT
        b.id,
        b.farmer_id,
        b.name,
        b.notes,
        b.status,
        b.created_at,
        u.full_name,
        COUNT(c.id) AS record_count,
        MAX(c.created_at) AS last_classification_at,
        (
            SELECT r.predicted_class FROM classification_records r
            WHERE r.batch_id = b.id
            ORDER BY r.created_at DESC LIMIT 1
        ) AS latest_stage,
        (
            SELECT r.confidence FROM classification_records r
            WHERE r.batch_id = b.id
            ORDER BY r.created_at DESC LIMIT 1
        ) AS latest_confidence,
        (
            SELECT r.filename FROM classification_records r
            WHERE r.batch_id = b.id
            ORDER BY r.created_at DESC LIMIT 1
        ) AS latest_filename
    FROM batches b
    LEFT JOIN users u ON u.id = b.farmer_id
    LEFT JOIN classification_records c ON c.batch_id = b.id
"""


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def init_roles():
    """Seeds the `roles` reference table.

    Activity 3, Part E requires `users.role_id` to be a foreign key onto
    `roles.id`, so this table has to exist *before* `users` is created. It is
    split out of `init_db()` for that reason and called first on startup.
    """
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS roles (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            description TEXT NOT NULL,
            can_submit_photos BOOLEAN NOT NULL DEFAULT FALSE,
            can_review_batches BOOLEAN NOT NULL DEFAULT FALSE
        )
    """)

    for name, description, submit, review in ROLES:
        cursor.execute("""
            INSERT INTO roles (name, description, can_submit_photos, can_review_batches)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (name) DO NOTHING
        """, (name, description, submit, review))

    conn.commit()
    cursor.close()
    conn.close()


def role_id_for(name: str) -> int | None:
    """The `roles.id` behind a role slug, or None for an unknown role."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT id FROM roles WHERE name = %s", (name,))
    row = cursor.fetchone()

    cursor.close()
    conn.close()

    return row[0] if row else None


def init_db():
    """Creates the four tables the activity document lists.

    Part A - Database and storage: PostgreSQL tables `users`, `roles`,
    `batches`, `classification_records`. (`users` is created by `auth.py`;
    run `init_roles()` and `init_auth_db()` first so the foreign keys can be
    declared.)
    """
    init_roles()

    conn = get_connection()
    cursor = conn.cursor()

    # ------------------------------------------- classification_records
    # Earlier builds called this table `classifications`. Rename it once so
    # nothing that was already recorded is lost.
    cursor.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'classifications'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'classification_records'
            ) THEN
                ALTER TABLE classifications RENAME TO classification_records;
            END IF;
        END $$;
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS classification_records (
            id SERIAL PRIMARY KEY,
            filename TEXT NOT NULL,
            predicted_class TEXT NOT NULL,
            confidence REAL NOT NULL,
            recommendation TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    for column, definition in (
        ("user_id", "INTEGER REFERENCES users(id) ON DELETE SET NULL"),
        # `batches` is created further down, so the foreign key for this one is
        # attached by the DO block after both tables exist.
        ("batch_id", "INTEGER"),
        ("batch_name", "TEXT"),
        ("notes", "TEXT"),
        ("quality_notes", "TEXT"),
        ("image_url", "TEXT"),
        ("engine", "TEXT"),
    ):
        cursor.execute(
            f"ALTER TABLE classification_records "
            f"ADD COLUMN IF NOT EXISTS {column} {definition}"
        )

    # ----------------------------------------------------------------- batches
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS batches (
            id SERIAL PRIMARY KEY,
            farmer_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            notes TEXT DEFAULT '',
            status TEXT NOT NULL DEFAULT 'Pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cursor.execute("ALTER TABLE batches ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT ''")
    cursor.execute("ALTER TABLE batches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'Pending'")

    # Activity 3, Part E names the owner column `farmer_id` ("FK farmer_id ->
    # users.id"). Earlier builds called it `user_id`; rename it in place so the
    # rows that already exist keep their owner.
    cursor.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'batches'
                  AND column_name = 'user_id'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'batches'
                  AND column_name = 'farmer_id'
            ) THEN
                ALTER TABLE batches RENAME COLUMN user_id TO farmer_id;
            END IF;
        END $$;
    """)
    cursor.execute(
        "ALTER TABLE batches "
        "ADD COLUMN IF NOT EXISTS farmer_id INTEGER REFERENCES users(id) ON DELETE CASCADE"
    )

    # The batch_id column above carries no foreign key yet because `batches`
    # did not exist when it was added. Attach it now if it is missing.
    cursor.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint
                WHERE conname = 'classification_records_batch_id_fkey'
            ) THEN
                ALTER TABLE classification_records
                    ADD CONSTRAINT classification_records_batch_id_fkey
                    FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE SET NULL;
            END IF;
        END $$;
    """)

    cursor.execute(
        "CREATE INDEX IF NOT EXISTS idx_records_user ON classification_records (user_id)"
    )
    cursor.execute(
        "CREATE INDEX IF NOT EXISTS idx_records_batch ON classification_records (batch_id)"
    )
    cursor.execute(
        "CREATE INDEX IF NOT EXISTS idx_batches_farmer ON batches (farmer_id)"
    )

    conn.commit()

    cursor.close()
    conn.close()

    print("Database tables are ready!")


def row_to_record(row) -> dict:
    """Maps a `classification_records` row to the JSON the API returns."""
    return {
        "id": row[0],
        "filename": row[1],
        "predicted_class": row[2],
        "confidence": row[3],
        "recommendation": row[4],
        "created_at": row[5],
        "user_id": row[6],
        "batch_id": row[7],
        "batch_name": row[8],
        "notes": row[9],
        "quality_notes": row[10],
        "image_url": row[11],
        "engine": row[12],
    }


def row_to_batch(row) -> dict:
    return {
        "id": row[0],
        "farmer_id": row[1],
        "name": row[2],
        "notes": row[3],
        "status": row[4],
        "created_at": row[5],
        "farmer": row[6],
        "record_count": row[7],
        "last_classification_at": row[8],
        "latest_stage": row[9],
        "latest_confidence": row[10],
        "latest_filename": row[11],
    }


def save_classification(
    filename: str,
    label: str,
    confidence: float,
    recommendation: str,
    user_id: int | None = None,
    batch_id: int | None = None,
    batch_name: str | None = None,
    notes: str | None = None,
    quality_notes: str | None = None,
    image_url: str | None = None,
    engine: str | None = None
):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO classification_records (
            filename,
            predicted_class,
            confidence,
            recommendation,
            user_id,
            batch_id,
            batch_name,
            notes,
            quality_notes,
            image_url,
            engine
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING id
    """, (
        filename,
        label,
        confidence,
        recommendation,
        user_id,
        batch_id,
        batch_name,
        notes,
        quality_notes,
        image_url,
        engine
    ))

    record_id = cursor.fetchone()[0]

    conn.commit()

    cursor.close()
    conn.close()

    return record_id


def get_all_classifications(user_id=None):
    """Every record, or only one farmer's records when ``user_id`` is given."""
    conn = get_connection()
    cursor = conn.cursor()

    columns = """
        id,
        filename,
        predicted_class,
        confidence,
        recommendation,
        created_at,
        user_id,
        batch_id,
        batch_name,
        notes,
        quality_notes,
        image_url,
        engine
    """

    if user_id is None:
        cursor.execute(f"""
            SELECT {columns}
            FROM classification_records
            ORDER BY created_at DESC
        """)
    else:
        cursor.execute(f"""
            SELECT {columns}
            FROM classification_records
            WHERE user_id = %s
            ORDER BY created_at DESC
        """, (user_id,))

    rows = cursor.fetchall()

    cursor.close()
    conn.close()

    return rows


# ------------------------------------------------------------------- batches

def _batch_by_id(batch_id) -> dict | None:
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(_BATCH_SELECT + " WHERE b.id = %s GROUP BY b.id, u.full_name", (batch_id,))
    row = cursor.fetchone()

    cursor.close()
    conn.close()

    return row_to_batch(row) if row else None


def create_batch(farmer_id: int, name: str, notes: str = "", status: str = "Pending") -> dict:
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO batches (farmer_id, name, notes, status)
        VALUES (%s, %s, %s, %s)
        RETURNING id
    """, (farmer_id, name, notes, status))

    batch_id = cursor.fetchone()[0]

    conn.commit()

    cursor.close()
    conn.close()

    return _batch_by_id(batch_id)


def save_batch_with_record(
    farmer_id: int,
    batch_name: str,
    batch_notes: str,
    filename: str,
    label: str,
    confidence: float,
    recommendation: str,
    record_notes: str | None = None,
    quality_notes: str | None = None,
    image_url: str | None = None,
    engine: str | None = None,
) -> dict:
    """Opens a batch and writes its first classification row in ONE transaction.

    Activity 3, Part E: *"Batch row and its first classification_records row
    are inserted in one transaction"*, so a photo can never end up attached to
    a batch that was rolled back, or a batch can never be left empty because
    its record failed.

    Returns the created record, with its `batch_id` and `batch_name` filled in.
    """
    conn = get_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("""
            INSERT INTO batches (farmer_id, name, notes, status)
            VALUES (%s, %s, %s, 'Classified')
            RETURNING id, created_at
        """, (farmer_id, batch_name, batch_notes))
        batch_id, batch_created_at = cursor.fetchone()

        cursor.execute("""
            INSERT INTO classification_records (
                filename, predicted_class, confidence, recommendation,
                user_id, batch_id, batch_name, notes, quality_notes,
                image_url, engine
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id, created_at
        """, (
            filename, label, confidence, recommendation,
            farmer_id, batch_id, batch_name, record_notes, quality_notes,
            image_url, engine
        ))
        record_id, record_created_at = cursor.fetchone()

        # Only now - both rows exist, so the pair is durable together.
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()

    return {
        "id": record_id,
        "created_at": record_created_at,
        "batch_id": batch_id,
        "batch_created_at": batch_created_at,
    }


def list_batches(farmer_id=None, start_date=None, end_date=None) -> list[dict]:
    """Every batch, or a filtered slice of them.

    Activity 3, Part D's contract for `GET /api/batches` is `farmer_id` plus a
    date range. Which of those a caller is allowed to ask for is decided by
    the API layer before it gets here.
    """
    clauses = []
    params = []

    if farmer_id is not None:
        clauses.append("b.farmer_id = %s")
        params.append(farmer_id)

    # `created_at` is a TIMESTAMP, so an inclusive end date has to become a
    # half-open range or a batch stamped 16:00 on the last day would be lost.
    if start_date:
        clauses.append("b.created_at >= %s::date")
        params.append(start_date)
    if end_date:
        clauses.append("b.created_at < (%s::date + INTERVAL '1 day')")
        params.append(end_date)

    sql = _BATCH_SELECT
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " GROUP BY b.id, u.full_name ORDER BY b.created_at DESC"

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(sql, tuple(params))
    rows = cursor.fetchall()

    cursor.close()
    conn.close()

    return [row_to_batch(row) for row in rows]


def get_batch_detail(batch_id: int) -> dict | None:
    """One batch and every classification record attached to it.

    Activity 3, Part D: `GET /api/batches/{id}` returns *"one batch with its
    classification records"*.
    """
    batch = _batch_by_id(batch_id)

    if batch is None:
        return None

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, filename, predicted_class, confidence, recommendation,
               created_at, user_id, batch_id, batch_name, notes,
               quality_notes, image_url, engine
        FROM classification_records
        WHERE batch_id = %s
        ORDER BY created_at DESC
    """, (batch_id,))

    records = [row_to_record(row) for row in cursor.fetchall()]

    cursor.close()
    conn.close()

    return {**batch, "records": records, "record_count": len(records)}


def get_batch_owner(batch_id) -> int | None:
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT farmer_id FROM batches WHERE id = %s", (batch_id,))
    row = cursor.fetchone()

    cursor.close()
    conn.close()

    return row[0] if row else None


def delete_batch(batch_id: int) -> bool:
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("DELETE FROM batches WHERE id = %s", (batch_id,))
    deleted = cursor.rowcount

    conn.commit()

    cursor.close()
    conn.close()

    return deleted > 0


# ------------------------------------------------------------------- trends

def fermentation_trends(user_id=None) -> dict:
    """Aggregation of batch / fermentation trend data for the dashboard.

    Part A - Business logic: "aggregation of batch/fermentation trend data for
    the dashboard".
    """
    conn = get_connection()
    cursor = conn.cursor()

    where = "WHERE user_id = %s" if user_id is not None else ""
    params = (user_id,) if user_id is not None else ()

    cursor.execute(f"""
        SELECT COUNT(*), COALESCE(AVG(confidence), 0)
        FROM classification_records {where}
    """, params)
    total_records, average_confidence = cursor.fetchone()

    cursor.execute(f"""
        SELECT predicted_class, COUNT(*), COALESCE(AVG(confidence), 0)
        FROM classification_records {where}
        GROUP BY predicted_class
    """, params)
    per_stage = {
        row[0]: {"count": row[1], "average_confidence": round(float(row[2]), 4)}
        for row in cursor.fetchall()
    }

    cursor.execute(f"""
        SELECT DATE(created_at), COUNT(*)
        FROM classification_records {where}
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) DESC
        LIMIT 14
    """, params)
    daily = [
        {"day": row[0].isoformat(), "count": row[1]}
        for row in cursor.fetchall()
    ][::-1]

    batch_where = "WHERE farmer_id = %s" if user_id is not None else ""
    cursor.execute(f"SELECT COUNT(*) FROM batches {batch_where}", params)
    total_batches = cursor.fetchone()[0]

    cursor.close()
    conn.close()

    stages = [
        {
            "stage": stage,
            "count": per_stage.get(stage, {}).get("count", 0),
            "average_confidence": per_stage.get(stage, {}).get("average_confidence", 0.0),
        }
        for stage in STAGES
    ]

    # Any label the model produced that is not one of the documented stages.
    unexpected = {k: v for k, v in per_stage.items() if k not in STAGES}

    return {
        "total_records": total_records,
        "total_batches": total_batches,
        "average_confidence": round(float(average_confidence or 0), 4),
        "stages": stages,
        "unexpected_stages": unexpected,
        "daily": daily,
    }


def get_roles() -> list[dict]:
    """The five actors seeded by [init_db] (Activity 2, Part A)."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT name, description, can_submit_photos, can_review_batches
        FROM roles
        ORDER BY id
    """)

    rows = [
        {
            "name": row[0],
            "description": row[1],
            "can_submit_photos": row[2],
            "can_review_batches": row[3],
        }
        for row in cursor.fetchall()
    ]

    cursor.close()
    conn.close()

    return rows


if __name__ == "__main__":
    from auth import init_auth_db

    # `users` has to exist before the foreign keys can be declared.
    init_auth_db()
    init_db()
