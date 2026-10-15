"""Reads the repository's `.env` into this process's environment.

Activity 3, Part F: *".env file with API_BASE_URL, DATABASE_URL, JWT_SECRET,
CLOUD_STORAGE_BUCKET, CNN_SERVICE_URL (the .env file is gitignored)"*.

Only the standard library is used, so satisfying that line costs the backend no
dependency. Two rules keep it honest:

  * an already-set variable always wins - a deployment supplies its secrets
    through the platform's secret store and the checked-out file simply never
    arrives, so nothing here can override it;
  * a missing `.env` is not an error - every setting has a local default, which
    is what lets a fresh clone run `RUN.bat` and do nothing else.
"""
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"

_loaded = False


def load_env(path: Path = ENV_FILE, *, reload: bool = False) -> dict:
    """Merges `KEY=VALUE` lines from `path` into os.environ. Idempotent.

    `reload` only bypasses the "read once" guard so a test can parse a second
    file; it does not change the precedence rule, which is unconditional -
    a variable that is already set is never replaced.

    Returns the variables the file actually set, which makes the behaviour
    testable without reaching into os.environ.
    """
    global _loaded

    if _loaded and not reload:
        return {}

    _loaded = True

    if not path.exists():
        return {}

    applied = {}

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()

        # Comments, blank lines, and the odd BOM a Windows editor leaves behind.
        if not line or line.startswith("#") or line.startswith("\ufeff"):
            continue

        if line.startswith("export "):
            line = line[len("export "):].strip()

        if "=" not in line:
            continue

        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()

        # Tolerate quoted values so a secret may contain a '#'.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]

        if not key or key in os.environ:
            continue

        os.environ[key] = value
        applied[key] = value

    return applied
