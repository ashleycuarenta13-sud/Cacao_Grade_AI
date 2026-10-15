"""Launches the CNN inference service, optionally over HTTPS.

    python run.py           http://127.0.0.1:8001   (default, plaintext)
    python run.py --ssl     https://127.0.0.1:8001

The certificate is shared with the backend: both services read
``Cacao/certs/``, so one make_cert.py run covers both hops of the workflow."""

import sys
from pathlib import Path

import uvicorn

CERT_DIR = Path(__file__).resolve().parent.parent / "certs"


def main() -> None:
    use_ssl = "--ssl" in sys.argv
    cert = CERT_DIR / "cert.pem"
    key = CERT_DIR / "key.pem"

    if use_ssl and not (cert.exists() and key.exists()):
        raise SystemExit(
            "No certificate found.\n"
            f"  Expected {cert}\n"
            f"  Expected {key}\n"
            "Generate them first (from backend/):\n"
            "    ..\\backend\\.venv\\Scripts\\python.exe ..\\backend\\make_cert.py"
        )

    scheme = "https" if use_ssl else "http"

    print(f"CacaoGrade AI CNN service on {scheme}://127.0.0.1:8001")

    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=8001,
        ssl_certfile=str(cert) if use_ssl else None,
        ssl_keyfile=str(key) if use_ssl else None,
    )


if __name__ == "__main__":
    main()
