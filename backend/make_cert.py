"""Generates the self-signed certificate the HTTPS setup uses.

Activity 2, Part A - Security controls: *"HTTPS for all client-server and
server-service communication."* That covers three hops in this project:

    Flutter client  ->  backend      (port 8000)
    backend         ->  CNN service  (port 8001)
    PostgreSQL                       (local socket in this project)

Run this once, then use RUN_SSL.bat and RUN_CNN_SSL.bat:

    .venv\\Scripts\\python.exe make_cert.py

It writes ``cert.pem`` and ``key.pem`` into ``Cacao/certs/``. A self-signed
certificate is right for the coursework deployment - it removes the plaintext
hop without needing a public hostname. **Do not use a self-signed certificate
for a real public deployment**: put the services behind a managed certificate
or a TLS-terminating load balancer instead.

Subject alternative names cover every address the services are reached by, so
clients can validate the certificate instead of disabling verification.
"""

import datetime
import ipaddress
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

CERT_DIR = Path(__file__).resolve().parent.parent / "certs"

# Every host name and address the two services are reached by.
DNS_NAMES = ["localhost", "cacao-grade-ai", "cacao-cnn"]
IP_ADDRESSES = [
    ipaddress.ip_address("127.0.0.1"),
    ipaddress.ip_address("::1"),
]

DAYS_VALID = 825  # browsers refuse to trust public certs past 825 days


def build() -> tuple[bytes, bytes]:
    key = ec.generate_private_key(ec.SECP256R1())

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "CacaoGrade AI"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "IT 110 - CacaoGrade AI"),
    ])

    now = datetime.datetime.now(datetime.timezone.utc)

    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=DAYS_VALID))
        .add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName(name) for name in DNS_NAMES
            ] + [
                x509.IPAddress(addr) for addr in IP_ADDRESSES
            ]),
            critical=False,
        )
        .add_extension(
            # Loops back to this same key, which is exactly what a self-signed
            # certificate means; recorded so the intent is explicit.
            x509.BasicConstraints(ca=True, path_length=0),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )

    cert_pem = cert.public_bytes(serialization.Encoding.PEM)
    key_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )

    return cert_pem, key_pem


def main() -> None:
    CERT_DIR.mkdir(parents=True, exist_ok=True)

    cert_pem, key_pem = build()

    cert_path = CERT_DIR / "cert.pem"
    key_path = CERT_DIR / "key.pem"

    cert_path.write_bytes(cert_pem)
    key_path.write_bytes(key_pem)

    # The private key is readable by anything that can read the project, so
    # tighten it before handing it to uvicorn.
    try:
        key_path.chmod(0o600)
    except OSError:
        pass  # Windows without a POSIX mode; the file stays as created.

    print(f"Wrote {cert_path}")
    print(f"Wrote {key_path}")
    print()
    print("Start the services over TLS with:")
    print("  RUN_SSL.bat        backend      -> https://127.0.0.1:8000")
    print("  RUN_CNN_SSL.bat    CNN service  -> https://127.0.0.1:8001")
    print()
    print("Then set in frontend/lib/core/api_service.dart:")
    print("  const kApiBaseUrl = 'https://127.0.0.1:8000';")


if __name__ == "__main__":
    main()
