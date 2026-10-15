import hashlib
import json
import os
import secrets
import time
from base64 import urlsafe_b64decode, urlsafe_b64encode
from pathlib import Path

from database import get_connection


PBKDF2_ITERATIONS = 260_000

# Activity 2, Part A - "JWT-based authentication issued at login".
#
# A JWT lets any service verify the signature and the expiry without touching
# the database, which is what the document's Cloud Run / microservice split
# needs. Its `jti` still points at a row in `sessions`, so the table acts as a
# revocation list: logging out really kills the bearer instead of leaving a
# token that works until it expires.
JWT_ALGORITHM = "HS256"
JWT_ISSUER = "cacao-grade-ai"

# 12 hours by default - long enough for a working day of cut tests, short
# enough that a leaked token ages out quickly. Override with
# CACAO_JWT_TTL (seconds).
JWT_TTL_SECONDS = int(os.getenv("CACAO_JWT_TTL", str(60 * 60 * 12)))

_SECRET_FILE = Path(__file__).resolve().parent / ".jwt_secret"


class AuthError(Exception):
    """Raised for any user registration / login problem."""


class TokenError(Exception):
    """Raised when a bearer token cannot be trusted."""


def _secret() -> bytes:
    """Signing key: CACAO_JWT_SECRET (or the document's name, JWT_SECRET) when
    set, otherwise a generated key persisted to `backend/.jwt_secret` so a dev
    restart keeps its sessions.

    Part F lists `JWT_SECRET` among the `.env` entries, so both spellings are
    accepted and neither may ever be committed.
    """
    env = os.getenv("CACAO_JWT_SECRET") or os.getenv("JWT_SECRET")

    if env:
        return env.encode("utf-8")

    if _SECRET_FILE.exists():
        return _SECRET_FILE.read_bytes().strip()

    key = secrets.token_hex(32).encode("utf-8")
    _SECRET_FILE.write_bytes(key)
    return key


def _b64url(data: bytes) -> str:
    return urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(text: str) -> bytes:
    return urlsafe_b64decode(text + "=" * (-len(text) % 4))


def issue_jwt(user_id: int, role: str, jti: str) -> str:
    """Mints the bearer handed back by login and register."""
    now = int(time.time())

    header = {"alg": JWT_ALGORITHM, "typ": "JWT"}
    claims = {
        "sub": user_id,
        "role": role,
        "jti": jti,
        "iat": now,
        "exp": now + JWT_TTL_SECONDS,
        "iss": JWT_ISSUER,
    }

    signing_input = (
        f"{_b64url(json.dumps(header, separators=(',', ':')).encode('utf-8'))}"
        f".{_b64url(json.dumps(claims, separators=(',', ':')).encode('utf-8'))}"
    )

    signature = hmac_digest(signing_input)
    return f"{signing_input}.{_b64url(signature)}"


def hmac_digest(signing_input: str) -> bytes:
    import hmac

    return hmac.new(
        _secret(), signing_input.encode("ascii"), hashlib.sha256
    ).digest()


def decode_jwt(token: str) -> dict:
    """Verifies signature, issuer and expiry, then returns the claims.

    Raises [TokenError] for anything that cannot be trusted.
    """
    parts = token.split(".")

    if len(parts) != 3:
        raise TokenError("Malformed token.")

    signing_input = f"{parts[0]}.{parts[1]}"

    try:
        actual = _b64url_decode(parts[2])
    except Exception as exc:
        raise TokenError("Malformed signature.") from exc

    if not secrets.compare_digest(hmac_digest(signing_input), actual):
        raise TokenError("Bad signature.")

    try:
        claims = json.loads(_b64url_decode(parts[1]))
    except Exception as exc:
        raise TokenError("Malformed claims.") from exc

    if claims.get("iss") != JWT_ISSUER:
        raise TokenError("Unexpected token issuer.")

    try:
        exp = int(claims["exp"])
    except (KeyError, TypeError, ValueError) as exc:
        raise TokenError("Token has no expiry.") from exc

    if exp < int(time.time()):
        raise TokenError("Session expired.")

    return claims


def init_auth_db():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            full_name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'farmer',
            contact TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Activity 3, Part E - `users` carries "PK id; unique email;
    # FK role_id -> roles.id". The role *name* stays on the row as well: it is
    # what the JWT, the API's role checks and every response payload use, while
    # `role_id` is the referential integrity the document asks the database to
    # enforce. `init_roles()` runs first so the key can be declared.
    cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS contact TEXT DEFAULT ''")
    cursor.execute(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS role_id INTEGER REFERENCES roles(id)"
    )
    cursor.execute("""
        UPDATE users
        SET role_id = r.id
        FROM roles r
        WHERE r.name = users.role AND users.role_id IS NULL
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.commit()
    cursor.close()
    conn.close()

    print("Auth tables are ready!")


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        bytes.fromhex(salt),
        PBKDF2_ITERATIONS
    )
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algorithm, iterations, salt, expected = stored.split("$")
        if algorithm != "pbkdf2_sha256":
            return False

        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt),
            int(iterations)
        )
        return secrets.compare_digest(digest.hex(), expected)
    except (ValueError, TypeError):
        return False


def _normalise_email(email: str) -> str:
    return email.strip().lower()


def _user_dict(row) -> dict:
    return {
        "id": row[0],
        "full_name": row[1],
        "email": row[2],
        "role": row[3],
        "created_at": row[4],
    }


def create_user(full_name: str, email: str, password: str, role: str = "farmer") -> dict:
    email = _normalise_email(email)
    password_hash = hash_password(password)

    conn = get_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("""
            INSERT INTO users (full_name, email, password_hash, role, role_id)
            VALUES (%s, %s, %s, %s, (SELECT id FROM roles WHERE name = %s))
            RETURNING id, full_name, email, role, created_at
        """, (full_name.strip(), email, password_hash, role, role))

        row = cursor.fetchone()
        conn.commit()
        return _user_dict(row)

    except Exception as exc:
        conn.rollback()

        if "duplicate key" in str(exc) and "users_email_key" in str(exc):
            raise AuthError("An account with this email already exists.") from exc

        raise AuthError("Could not create the account.") from exc

    finally:
        cursor.close()
        conn.close()


def get_user_by_email(email: str):
    email = _normalise_email(email)

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, full_name, email, password_hash, role, created_at
        FROM users
        WHERE email = %s
    """, (email,))

    row = cursor.fetchone()

    cursor.close()
    conn.close()

    if row is None:
        return None

    return {
        "id": row[0],
        "full_name": row[1],
        "email": row[2],
        "password_hash": row[3],
        "role": row[4],
        "created_at": row[5],
    }


def authenticate(email: str, password: str) -> dict:
    user = get_user_by_email(email)

    if user is None or not verify_password(password, user["password_hash"]):
        raise AuthError("Incorrect email or password.")

    return _user_dict((
        user["id"],
        user["full_name"],
        user["email"],
        user["role"],
        user["created_at"],
    ))


def create_session(user_id: int, role: str = "farmer") -> str:
    """Opens a session and returns the JWT the client should send back.

    The random `jti` is what is stored in `sessions`; the client only ever
    sees the signed token that wraps it.
    """
    jti = secrets.token_hex(32)

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO sessions (user_id, token)
        VALUES (%s, %s)
    """, (user_id, jti))

    conn.commit()
    cursor.close()
    conn.close()

    return issue_jwt(user_id, role, jti)


def get_user_by_token(token: str):
    """Resolves a bearer token to its account, or None if it is not trusted.

    The signature and expiry are checked without a database round-trip; the
    session row is then consulted as the revocation list. The account is read
    back rather than taken from the token's `role` claim, so an administrator
    changing somebody's role takes effect on the very next request.
    """
    if not token:
        return None

    try:
        claims = decode_jwt(token)
    except TokenError:
        return None

    jti = claims.get("jti")

    if not jti or not isinstance(jti, str):
        return None

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT u.id, u.full_name, u.email, u.role, u.created_at
        FROM sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token = %s
    """, (jti,))

    row = cursor.fetchone()

    cursor.close()
    conn.close()

    if row is None:
        return None

    return _user_dict(row)


def delete_session(token: str) -> bool:
    """Revokes a bearer by deleting the `jti` it wraps."""
    if not token:
        return False

    try:
        claims = decode_jwt(token)
    except TokenError:
        return False

    jti = claims.get("jti")

    if not jti or not isinstance(jti, str):
        return False

    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("DELETE FROM sessions WHERE token = %s", (jti,))
    deleted = cursor.rowcount

    conn.commit()
    cursor.close()
    conn.close()

    return deleted > 0


def purge_expired_sessions() -> int:
    """Drops sessions whose JWT can no longer be valid.

    Called on startup so the table does not grow without bound on a long-lived
    deployment.
    """
    cutoff = int(time.time()) - JWT_TTL_SECONDS

    conn = get_connection()
    cursor = conn.cursor()

    # Sessions older than the TTL can only belong to expired tokens, whatever
    # their clock says.
    cursor.execute(
        "DELETE FROM sessions WHERE created_at < NOW() - (%s || ' seconds')::interval",
        (str(JWT_TTL_SECONDS),),
    )
    removed = cursor.rowcount

    conn.commit()
    cursor.close()
    conn.close()

    if removed:
        print(f"Purged {removed} expired session(s); {cutoff} is the token horizon.")

    return removed


def extract_bearer_token(authorization: str) -> str:
    if not authorization:
        return ""

    parts = authorization.split(" ", 1)

    if len(parts) != 2 or parts[0].lower() != "bearer":
        return ""

    return parts[1].strip()


def list_users():
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, full_name, email, role, created_at
        FROM users
        ORDER BY created_at DESC
    """)

    rows = cursor.fetchall()

    cursor.close()
    conn.close()

    return rows


def update_user_role(user_id: int, role: str) -> dict | None:
    """Re-points an account to one of the five documented roles.

    Returns the refreshed account, or None when no row matched the id. The
    caller has already checked that the actor is an administrator, so this
    function only has to reject a role the `roles` table does not know.
    """
    conn = get_connection()
    cursor = conn.cursor()

    try:
        # The `roles` registry is the source of truth, and Part E wants the
        # foreign key to carry it, so both columns are written together rather
        # than letting `role_id` drift behind the name.
        cursor.execute("SELECT id FROM roles WHERE name = %s", (role,))

        row = cursor.fetchone()

        if row is None:
            raise AuthError("That role is not registered in the roles table.")

        role_id = row[0]

        cursor.execute("""
            UPDATE users
            SET role = %s, role_id = %s
            WHERE id = %s
            RETURNING id, full_name, email, role, created_at
        """, (role, role_id, user_id))

        row = cursor.fetchone()

        if row is None:
            conn.rollback()
            return None

        conn.commit()
        return _user_dict(row)

    except AuthError:
        raise

    except Exception as exc:
        conn.rollback()
        raise AuthError("Could not change the account role.") from exc

    finally:
        cursor.close()
        conn.close()


# ------------------------------------------------------------------- profile
#
# Activity 3, Part D's "Minimum API Contract Worksheet" lists two profile
# operations that belong to any authenticated role:
#
#     GET /api/auth/profile   -> 200 + user JSON / 401
#     PUT /api/auth/profile   -> 200 + updated user / 400
#
# The role is deliberately not editable here. Changing it is an
# administrator's call and goes through PATCH /api/admin/users/{id}.

def _profile_dict(row) -> dict:
    return {
        "id": row[0],
        "full_name": row[1],
        "email": row[2],
        "role": row[3],
        "contact": row[4] or "",
        "created_at": row[5],
    }


def get_profile(user_id: int) -> dict | None:
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, full_name, email, role, contact, created_at
        FROM users WHERE id = %s
    """, (user_id,))

    row = cursor.fetchone()

    cursor.close()
    conn.close()

    return _profile_dict(row) if row else None


def update_user_profile(user_id: int, full_name=None, contact=None, email=None) -> dict | None:
    """Validates and updates the requesting user's row.

    Only the fields that were actually sent are changed, so a client that
    wants to fix its phone number does not accidentally blank out its name.
    """
    conn = get_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("""
            SELECT id, full_name, email, role, contact
            FROM users WHERE id = %s
        """, (user_id,))

        current = cursor.fetchone()

        if current is None:
            return None

        new_name = (full_name if full_name is not None else current[1]).strip()
        new_contact = (contact if contact is not None else current[4]) or ""
        new_email = _normalise_email(email) if email else current[2]

        if not new_name:
            raise AuthError("The name cannot be empty.")

        cursor.execute("""
            UPDATE users
            SET full_name = %s, contact = %s, email = %s
            WHERE id = %s
            RETURNING id, full_name, email, role, contact, created_at
        """, (new_name, new_contact, new_email, user_id))

        row = cursor.fetchone()
        conn.commit()

        return _profile_dict(row)

    except AuthError:
        conn.rollback()
        raise

    except Exception as exc:
        conn.rollback()

        if "duplicate key" in str(exc) and "users_email_key" in str(exc):
            raise AuthError("Another account already uses this email.") from exc

        raise AuthError("Could not update the profile.") from exc

    finally:
        cursor.close()
        conn.close()
