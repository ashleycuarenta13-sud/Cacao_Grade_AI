"""Launches the backend, optionally over HTTPS.

    python run.py           http://127.0.0.1:8000   (default, plaintext)
    python run.py --ssl     https://127.0.0.1:8000

Activity 2, Part A - Security controls asks for HTTPS on every hop. RUN.bat
stays plaintext so the coursework setup keeps working without a certificate;
RUN_SSL.bat passes --ssl once make_cert.py has written certs/."""

import os
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
            "Generate them first:\n"
            "    .venv\\Scripts\\python.exe make_cert.py"
        )

    if use_ssl:
        # `main` reads these at import time, so they have to be in place
        # before uvicorn pulls the application in. Pointing the inference hop
        # at TLS and trusting our own certificate is what keeps
        # "HTTPS for all ... server-service communication" true by default
        # rather than by remembering two environment variables.
        os.environ.setdefault(
            "CACAO_CNN_URL", "https://127.0.0.1:8001/predict"
        )
        os.environ.setdefault("CACAO_CNN_CA", str(cert))

    scheme = "https" if use_ssl else "http"

    print(f"CacaoGrade AI backend on {scheme}://127.0.0.1:8000")

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        ssl_certfile=str(cert) if use_ssl else None,
        ssl_keyfile=str(key) if use_ssl else None,
    )


if __name__ == "__main__":
    main()
