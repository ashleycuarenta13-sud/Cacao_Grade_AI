"""Unit checks for envfile.load_env() - the `.env` reader Part F asks for.

Run:  .venv\\Scripts\\python.exe test_envfile.py
"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from envfile import load_env  # noqa: E402

PASSED = 0
FAILED = 0


def check(label, ok, detail=""):
    global PASSED, FAILED
    PASSED += ok
    FAILED += not ok
    print(f"  [{'OK' if ok else 'FAIL'}] {label}{(' - ' + detail) if detail else ''}")


def main():
    tmp = Path(tempfile.mkdtemp())
    env = tmp / "sample.env"

    env.write_text(
        "\ufeff# a comment\n"
        "\n"
        "   \n"
        "export EXPORTED=yes\n"
        "PLAIN=value\n"
        "QUOTED=\"has # inside\"\n"
        "SINGLE='also ok'\n"
        "NO_EQUALS\n"
        "EMPTY=\n",
        encoding="utf-8",
    )

    saved = dict(os.environ)
    os.environ.pop("EXPORTED", None)
    os.environ.pop("PLAIN", None)
    os.environ.pop("QUOTED", None)
    os.environ.pop("SINGLE", None)
    os.environ.pop("NO_EQUALS", None)
    os.environ.pop("EMPTY", None)

    try:
        applied = load_env(env, reload=True)

        check("export prefix stripped", applied.get("EXPORTED") == "yes",
              str(applied.get("EXPORTED")))
        check("plain assignment read", applied.get("PLAIN") == "value",
              str(applied.get("PLAIN")))
        check("double-quoted value unquoted and keeps '#'",
              applied.get("QUOTED") == "has # inside", str(applied.get("QUOTED")))
        check("single-quoted value unquoted", applied.get("SINGLE") == "also ok",
              str(applied.get("SINGLE")))
        check("an empty value is honoured", "EMPTY" in applied, str(sorted(applied)))
        check("a line without '=' is skipped", "NO_EQUALS" not in applied)
        check("nothing leaks into os.environ for the skipped line",
              "NO_EQUALS" not in os.environ)
        check("comment and blank lines produce no keys",
              not any(k.startswith("#") for k in applied))

        # An already-set variable must win over the file.
        os.environ["PLAIN"] = "from-shell"
        reload = load_env(env, reload=True)
        check("an existing environment variable is not overwritten",
              os.environ["PLAIN"] == "from-shell" and "PLAIN" not in reload,
              str(reload.get("PLAIN")))

        # Missing file is not an error.
        gone = load_env(tmp / "absent.env", reload=True)
        check("a missing .env is not an error", gone == {}, str(gone))

        # The repository's own .env (if present) parses.
        root = Path(__file__).resolve().parent.parent / ".env"
        if root.exists():
            parsed = load_env(root, reload=True)
            check("the repository .env parses", isinstance(parsed, dict),
                  f"{root.name} read")
        else:
            print("  [skip] no .env at the repository root")

    finally:
        os.environ.clear()
        os.environ.update(saved)

    print(f"\n{'=' * 46}\n{PASSED} passed, {FAILED} failed")
    sys.exit(1 if FAILED else 0)


if __name__ == "__main__":
    main()
