"""End-to-end check of the Activity 2 workflow.

Requires both services to be running. The endpoints are configurable so the
same suite covers the plaintext coursework setup and the HTTPS one:

    backend     http://127.0.0.1:8000   (or https://127.0.0.1:8000)
    cnn_service http://127.0.0.1:8001   (or https://127.0.0.1:8001)

Run:        .venv\\Scripts\\python.exe e2e_test.py
Over TLS:   set CACAO_API=https://127.0.0.1:8000
            set CACAO_CNN=https://127.0.0.1:8001
            .venv\\Scripts\\python.exe e2e_test.py

The self-signed certificate from make_cert.py is trusted automatically when it
is present, so TLS runs verify the certificate instead of skipping it.
"""
import os
import sys
from pathlib import Path

import httpx

API = os.getenv("CACAO_API", "http://127.0.0.1:8000")
CNN = os.getenv("CACAO_CNN", "http://127.0.0.1:8001")

ASSETS = Path(__file__).resolve().parent.parent / "frontend" / "assets" / "images"
CERT_PEM = Path(__file__).resolve().parent.parent / "certs" / "cert.pem"


def _verify():
    """Trust our own certificate when a hop is HTTPS."""
    if not (API.startswith("https://") or CNN.startswith("https://")):
        return True

    override = os.getenv("CACAO_CA")
    if override:
        return override

    return str(CERT_PEM) if CERT_PEM.exists() else True


CLIENT = httpx.Client(verify=_verify(), timeout=60)


def _b64json(segment: str) -> dict:
    """Decodes one JWT segment so the test can assert on its contents."""
    import base64
    import json

    padded = segment + "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))


PASSED = 0
FAILED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED, FAILED
    PASSED += ok
    FAILED += not ok
    print(f"  [{'OK' if ok else 'FAIL'}] {label}{(' - ' + detail) if detail else ''}")


def login(email: str) -> dict:
    response = CLIENT.post(
        f"{API}/api/auth/login",
        json={"email": email, "password": "password123"},
        timeout=20,
    )
    response.raise_for_status()
    return response.json()


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def upload(token: str, image: bytes, name: str = "cuttest.jpg", **data) -> httpx.Response:
    return CLIENT.post(
        f"{API}/api/classify",
        files={"file": (name, image, "image/jpeg")},
        data=data,
        headers=auth(token),
        timeout=40,
    )


def main() -> None:
    print("1. Backend reachable")
    health = CLIENT.get(f"{API}/health", timeout=10).json()
    check("backend running", health.get("backend") == "running")
    check("database connected", health.get("database") == "connected")

    print("\n2. CNN inference service")
    cnn = CLIENT.get(f"{CNN}/health", timeout=10).json()
    check("cnn service ready", cnn.get("ready") is True, f"engine={cnn.get('engine')}")
    check("4 fermentation classes", len(cnn.get("classes", [])) == 4)

    print("\n3. DB schema - the four tables Part A lists")
    from database import get_connection

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'public'"
    )
    tables = {row[0] for row in cur.fetchall()}
    for table in ("users", "roles", "batches", "classification_records"):
        check(f"table {table}", table in tables)
    check("old 'classifications' table renamed",
          "classifications" not in tables)

    cur.execute(
        "SELECT name FROM roles ORDER BY name"
    )
    role_names = {row[0] for row in cur.fetchall()}
    for role in ("farmer", "staff", "buyer", "extension_worker", "admin"):
        check(f"roles.{role}", role in role_names)
    check("roles has 5 documented actors", len(role_names) == 5, str(sorted(role_names)))

    cur.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name = 'classification_records'"
    )
    columns = {row[0] for row in cur.fetchall()}
    for column in ("user_id", "batch_id", "quality_notes", "image_url", "engine"):
        check(f"classification_records.{column}", column in columns)

    cur.close()
    conn.close()

    print("\n4. Authentication + role check (Part D, step 4)")
    anon = upload(b"", ASSETS.joinpath("cacao-beans.png").read_bytes())
    check("no token -> 401", anon.status_code == 401, str(anon.status_code))

    farmer = login("rico@example.com")
    other_farmer = login("ashley@example.com")
    admin = login("admin@example.com")
    farmer_token = farmer["token"]
    admin_token = admin["token"]
    check("farmer logged in", farmer["user"]["role"] == "farmer")
    check("second farmer logged in", other_farmer["user"]["role"] == "farmer")

    print("\n5. Classification (Part D, steps 5-9)")
    image = ASSETS.joinpath("cacao-beans.png").read_bytes()
    result = upload(
        farmer_token,
        image,
        name="cut-test-001.jpg",
        batch_name="IT110 Demo Batch",
        notes="Harvested from the north plot.",
    )
    body = result.json()
    check("classify -> 200", result.status_code == 200, str(result.status_code))
    check("predicted_class present", bool(body.get("predicted_class")),
          str(body.get("predicted_class")))
    check("confidence present", isinstance(body.get("confidence"), (int, float)))
    check("quality_notes present", bool(body.get("quality_notes")))
    check("recommendation present", bool(body.get("recommendation")))
    check("image_url present", str(body.get("image_url", "")).startswith("/uploads/"))
    check("record id returned", bool(body.get("id")))
    check("a batch was opened for the photo", bool(body.get("batch_id")))
    print(f"        -> {body.get('predicted_class')} "
          f"({body.get('confidence')}) engine={body.get('engine')} "
          f"batch={body.get('batch_id')}")

    print("\n6. Stored photo is retrievable (Part D, step 5)")
    image_url = body.get("image_url")
    stored = CLIENT.get(f"{API}{image_url}", timeout=10)
    check("stored image downloads", stored.status_code == 200, str(stored.status_code))
    check("stored extension matches the real format",
          stored.content[:2] in (b"\x89P", b"\xff\xd8"),
          f"{image_url} -> {len(stored.content)} bytes")

    print("\n7. /api/batches (Part A - endpoint list)")
    own_batches = CLIENT.get(f"{API}/api/batches", headers=auth(farmer_token), timeout=20).json()
    check("farmer batch scope is 'own'", own_batches.get("scope") == "own")
    check("farmer sees the batch from step 5",
          own_batches.get("count", 0) >= 1, f"count={own_batches.get('count')}")
    first = own_batches["data"][0] if own_batches.get("data") else {}
    check("batch carries its owner", first.get("farmer") == farmer["user"]["full_name"])
    check("batch owner column is farmer_id (Part E)",
          "farmer_id" in first and "user_id" not in first,
          ",".join(sorted(first.keys())))
    check("batch counts its classification records",
          first.get("record_count") is not None)

    created = CLIENT.post(
        f"{API}/api/batches",
        json={"name": "Pre-registration batch", "notes": "Opened before grading."},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("POST /api/batches -> 200", created.status_code == 200, str(created.status_code))
    created_id = created.json().get("batch", {}).get("id")
    check("new batch id returned", bool(created_id), str(created_id))
    check("new batch starts as Pending",
          created.json().get("batch", {}).get("status") == "Pending")

    empty_name = CLIENT.post(
        f"{API}/api/batches",
        json={"name": ""},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("blank batch name rejected", empty_name.status_code == 400,
          str(empty_name.status_code))

    forbidden = CLIENT.delete(
        f"{API}/api/batches/{created_id}",
        headers=auth(other_farmer["token"]),
        timeout=20,
    )
    check("another farmer cannot delete it -> 403", forbidden.status_code == 403,
          str(forbidden.status_code))

    removed = CLIENT.delete(
        f"{API}/api/batches/{created_id}",
        headers=auth(farmer_token),
        timeout=20,
    )
    check("owner can delete it -> 200", removed.status_code == 200, str(removed.status_code))

    gone = CLIENT.get(f"{API}/api/batches", headers=auth(farmer_token), timeout=20).json()
    check("deleted batch is gone", all(b.get("id") != created_id for b in gone.get("data", [])))

    print("\n8. Batch history scope (farmer = own, staff/admin = all)")
    own = CLIENT.get(f"{API}/api/history", headers=auth(farmer_token), timeout=20).json()
    check("farmer history scoped to own records", own.get("scope") == "own")
    check("farmer record saved", own.get("count", 0) >= 1, f"count={own.get('count')}")
    saved = own["data"][0] if own.get("data") else {}
    check("saved record keeps the batch name",
          saved.get("batch_name") == "IT110 Demo Batch")
    check("saved record links to its batch", bool(saved.get("batch_id")))

    everything = CLIENT.get(f"{API}/api/history", headers=auth(admin_token), timeout=20).json()
    check("admin history scope is 'all'", everything.get("scope") == "all")
    check("admin sees at least as many records",
          everything.get("count", 0) >= own.get("count", 0),
          f"admin={everything.get('count')} farmer={own.get('count')}")

    print("\n9. /api/trends - aggregation for the dashboard (Part A)")
    trends = CLIENT.get(f"{API}/api/trends", headers=auth(farmer_token), timeout=20)
    t = trends.json()
    check("trends -> 200", trends.status_code == 200, str(trends.status_code))
    check("trends scoped to the farmer", t.get("scope") == "own")
    check("total_records counted", t.get("total_records", 0) >= 1,
          str(t.get("total_records")))
    check("total_batches counted", t.get("total_batches", 0) >= 1,
          str(t.get("total_batches")))
    check("average_confidence in 0..1", 0.0 <= float(t.get("average_confidence", -1)) <= 1.0,
          str(t.get("average_confidence")))
    stages = t.get("stages", [])
    check("all 4 stages reported", len(stages) == 4, str([s.get("stage") for s in stages]))
    check("stage counts sum to the record count",
          sum(s.get("count", 0) for s in stages) == t.get("total_records"),
          f"stages={sum(s.get('count', 0) for s in stages)} "
          f"total={t.get('total_records')}")
    check("daily series present", isinstance(t.get("daily"), list),
          f"{len(t.get('daily', []))} days")

    print("\n10. Server-side validation (Part A - business logic)")
    bad_type = CLIENT.post(
        f"{API}/api/classify",
        files={"file": ("notes.txt", b"not an image", "text/plain")},
        headers=auth(farmer_token),
        timeout=20,
    )
    # Activity 3, Part D gives POST /api/classify a single failure code: 422.
    check("non-image rejected -> 422", bad_type.status_code == 422, str(bad_type.status_code))

    empty = upload(farmer_token, b"")
    check("empty image rejected -> 422", empty.status_code == 422, str(empty.status_code))

    # A .jpg whose bytes are not an image reaches the CNN, which cannot decode
    # it and answers 4xx. The API has to pass that through as a 422 rather than
    # a 502, because Part E asks the client to queue only what a retry could
    # fix - an unreadable photo would fail identically forever.
    unreadable = upload(farmer_token, b"\xff\xd8\xff\xe0not-really-a-jpeg",
                        name="broken.jpg")
    check("an unreadable image is a client error, not a service error",
          unreadable.status_code == 422, str(unreadable.status_code))
    check("it says the image could not be read",
          "could not read" in unreadable.text.lower(),
          unreadable.text[:90])

    print("\n11. Roles - the five actors Part A lists")
    roles_resp = CLIENT.get(f"{API}/api/roles", headers=auth(admin_token), timeout=20)
    roles = roles_resp.json()
    check("GET /api/roles -> 200", roles_resp.status_code == 200, str(roles_resp.status_code))
    check("roles requires a session",
          CLIENT.get(f"{API}/api/roles", timeout=20).status_code == 401)

    role_names = {r["name"] for r in roles.get("data", [])}
    check("all five documented actors present", role_names == {
        "farmer", "staff", "buyer", "extension_worker", "admin"},
        str(sorted(role_names)))
    check("each role describes itself",
          all(r.get("description") for r in roles.get("data", [])))

    # Reuse the second farmer account for the role round-trip so rico stays
    # a farmer for the checks above.
    target_id = other_farmer["user"]["id"]
    original_role = other_farmer["user"]["role"]

    promoted = CLIENT.patch(
        f"{API}/api/admin/users/{target_id}",
        json={"role": "buyer"},
        headers=auth(admin_token),
        timeout=20,
    )
    check("admin assigns 'buyer' -> 200", promoted.status_code == 200,
          str(promoted.status_code))
    check("buyer role stored", promoted.json().get("user", {}).get("role") == "buyer")

    human = CLIENT.patch(
        f"{API}/api/admin/users/{target_id}",
        json={"role": "Agricultural Extension Worker"},
        headers=auth(admin_token),
        timeout=20,
    )
    check("document's actor name is accepted",
          human.json().get("user", {}).get("role") == "extension_worker",
          str(human.json().get("user", {}).get("role")))

    # An extension worker watches every farmer, so it must not be scoped down.
    worker_token = login("ashley@example.com")["token"]
    worker_batches = CLIENT.get(f"{API}/api/batches", headers=auth(worker_token),
                               timeout=20).json()
    check("extension worker sees every batch", worker_batches.get("scope") == "all",
          str(worker_batches.get("scope")))

    worker_delete = CLIENT.delete(f"{API}/api/batches/999999",
                                 headers=auth(worker_token), timeout=20)
    check("extension worker cannot delete a batch -> 403",
          worker_delete.status_code == 403, str(worker_delete.status_code))

    worker_create = CLIENT.post(
        f"{API}/api/batches",
        json={"name": "Worker-owned batch"},
        headers=auth(worker_token),
        timeout=20,
    )
    check("extension worker cannot create a batch -> 403",
          worker_create.status_code == 403, str(worker_create.status_code))

    worker_classify = CLIENT.post(
        f"{API}/api/classify",
        files={"file": ("x.jpg", image, "image/jpeg")},
        data={"batch_name": "Worker batch"},
        headers=auth(worker_token),
        timeout=40,
    )
    check("extension worker cannot classify -> 403",
          worker_classify.status_code == 403, str(worker_classify.status_code))

    bad_role = CLIENT.patch(
        f"{API}/api/admin/users/{target_id}",
        json={"role": "astronaut"},
        headers=auth(admin_token),
        timeout=20,
    )
    check("unknown role rejected -> 400", bad_role.status_code == 400,
          str(bad_role.status_code))

    self_demote = CLIENT.patch(
        f"{API}/api/admin/users/{admin['user']['id']}",
        json={"role": "farmer"},
        headers=auth(admin_token),
        timeout=20,
    )
    check("admin cannot demote themselves -> 400", self_demote.status_code == 400,
          str(self_demote.status_code))

    farmer_patch = CLIENT.patch(
        f"{API}/api/admin/users/{target_id}",
        json={"role": "admin"},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("a farmer cannot assign roles -> 403", farmer_patch.status_code == 403,
          str(farmer_patch.status_code))

    restored = CLIENT.patch(
        f"{API}/api/admin/users/{target_id}",
        json={"role": original_role},
        headers=auth(admin_token),
        timeout=20,
    )
    check("role round-trip restores the original",
          restored.json().get("user", {}).get("role") == original_role)

    print("\n12. JWT (Part A - JWT-based authentication issued at login)")
    # Ashley is back to `farmer` after the role round-trip above, so this is a
    # clean session to open and then throw away.
    throwaway = login("ashley@example.com")
    bearer = throwaway["token"]

    check("login issues a compact JWT", bearer.count(".") == 2,
          f"{bearer[:28]}...")
    header = _b64json(bearer.split(".")[0])
    claims = _b64json(bearer.split(".")[1])

    check("header names HS256", header.get("alg") == "HS256", str(header))
    check("claims carry the subject",
          claims.get("sub") == throwaway["user"]["id"], str(claims.get("sub")))
    check("claims carry the role", claims.get("role") == throwaway["user"]["role"],
          str(claims.get("role")))
    check("claims carry a session id", bool(claims.get("jti")))
    check("claims carry an issuer", claims.get("iss") == "cacao-grade-ai",
          str(claims.get("iss")))
    check("claims expire in the future",
          int(claims.get("exp", 0)) > int(claims.get("iat", 0)))

    ok_read = CLIENT.get(f"{API}/api/history", headers=auth(bearer), timeout=20)
    check("the issued JWT is accepted", ok_read.status_code == 200,
          str(ok_read.status_code))

    parts = bearer.split(".")
    check("a forged signature is refused -> 401",
          CLIENT.get(f"{API}/api/history",
                     headers=auth(f"{parts[0]}.{parts[1]}.{'A' * 43}"),
                     timeout=20).status_code == 401)

    check("a bare three-part string is refused -> 401",
          CLIENT.get(f"{API}/api/history", headers=auth("not.a.jwt"),
                     timeout=20).status_code == 401)

    check("a truncated JWT is refused -> 401",
          CLIENT.get(f"{API}/api/history",
                     headers=auth(f"{parts[0]}.{parts[1]}."),
                     timeout=20).status_code == 401)

    check("a non-bearer Authorization header is refused -> 401",
          CLIENT.get(f"{API}/api/history",
                     headers={"Authorization": f"Token {bearer}"},
                     timeout=20).status_code == 401)

    signed_out = CLIENT.post(f"{API}/api/auth/logout", headers=auth(bearer),
                             timeout=20)
    check("logout is accepted", signed_out.status_code == 200,
          str(signed_out.status_code))
    check("logout revokes the JWT -> 401",
          CLIENT.get(f"{API}/api/history", headers=auth(bearer),
                     timeout=20).status_code == 401)

    print("\n13. Transport (Part A - HTTPS on every hop)")
    check("backend endpoint in use", API.startswith(("http://", "https://")), API)

    if API.startswith("https://"):
        probe = CLIENT.get(f"{API}/health", timeout=10)
        check("backend answers over TLS", probe.url.scheme == "https",
              str(probe.url.scheme))
        check("the certificate is trusted rather than skipped", bool(_verify()),
              str(_verify()))

        # A TLS listener cannot parse a plaintext request, so it closes.
        import socket

        sock = socket.create_connection(("127.0.0.1", 8000), timeout=5)
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")
        try:
            greeting = sock.recv(64)
        except OSError:
            greeting = b""
        finally:
            sock.close()

        check("plaintext is refused on the TLS port",
              not greeting.startswith(b"HTTP/"), repr(greeting[:40]))
    else:
        print("  [skip] backend is on plaintext - set CACAO_API to check TLS")

    if CNN.startswith("https://"):
        check("CNN service answers over TLS",
              CLIENT.get(f"{CNN}/health", timeout=10).url.scheme == "https")
    else:
        print("  [skip] CNN service is on plaintext - set CACAO_CNN to check TLS")

    print("\n14. Activity 3 - profile contract (Part D)")
    from datetime import datetime as _date

    # ---- GET /api/auth/profile -----------------------------------------
    anon_profile = CLIENT.get(f"{API}/api/auth/profile", timeout=20)
    check("GET /api/auth/profile without a token -> 401",
          anon_profile.status_code == 401, str(anon_profile.status_code))

    mine = CLIENT.get(f"{API}/api/auth/profile", headers=auth(farmer_token), timeout=20)
    check("GET /api/auth/profile -> 200", mine.status_code == 200, str(mine.status_code))
    profile = mine.json().get("user", {})
    for field in ("id", "full_name", "email", "role", "contact"):
        check(f"profile exposes {field}", field in profile, ",".join(sorted(profile)))

    # ---- PUT /api/auth/profile -----------------------------------------
    saved_contact = "+63 917 000 1234"
    updated = CLIENT.put(
        f"{API}/api/auth/profile",
        json={"contact": saved_contact},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("PUT /api/auth/profile -> 200", updated.status_code == 200,
          str(updated.status_code))
    check("contact persisted", updated.json().get("user", {}).get("contact") == saved_contact,
          str(updated.json().get("user", {}).get("contact")))
    check("a partial update does not blank the name",
          bool(updated.json().get("user", {}).get("full_name")))
    check("a partial update does not blank the email",
          bool(updated.json().get("user", {}).get("email")))

    blank_name = CLIENT.put(
        f"{API}/api/auth/profile",
        json={"full_name": "   "},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("blank name -> 400", blank_name.status_code == 400, str(blank_name.status_code))

    taken_email = CLIENT.put(
        f"{API}/api/auth/profile",
        json={"email": "admin@example.com"},
        headers=auth(farmer_token),
        timeout=20,
    )
    check("taking another account's email -> 400",
          taken_email.status_code == 400, str(taken_email.status_code))

    # A self-service edit must never be a privilege-escalation path.
    CLIENT.put(f"{API}/api/auth/profile", json={"role": "admin"},
               headers=auth(farmer_token), timeout=20)
    still_farmer = CLIENT.get(f"{API}/api/auth/profile",
                              headers=auth(farmer_token), timeout=20
                              ).json().get("user", {}).get("role")
    check("role cannot be edited through the profile endpoint",
          still_farmer == "farmer", str(still_farmer))

    print("\n15. Activity 3 - batch detail + filters (Part D)")

    listing = CLIENT.get(f"{API}/api/batches", headers=auth(farmer_token), timeout=20).json()
    sample = listing["data"][0] if listing.get("data") else None
    check("a batch exists to open", bool(sample), f"count={listing.get('count')}")

    if sample:
        detail = CLIENT.get(f"{API}/api/batches/{sample['id']}",
                            headers=auth(farmer_token), timeout=20)
        check("GET /api/batches/{id} -> 200", detail.status_code == 200,
              str(detail.status_code))
        inner = detail.json().get("batch", {})
        check("batch detail carries its classification records",
              isinstance(inner.get("records"), list))
        check("batch detail counts them consistently",
              inner.get("record_count") == len(inner.get("records", [])),
              f"{inner.get('record_count')} vs {len(inner.get('records', []))}")

        missing = CLIENT.get(f"{API}/api/batches/99999999",
                             headers=auth(admin_token), timeout=20)
        check("unknown batch -> 404", missing.status_code == 404, str(missing.status_code))

        pry = CLIENT.get(f"{API}/api/batches/{sample['id']}",
                         headers=auth(other_farmer["token"]), timeout=20)
        check("another farmer cannot open it -> 403", pry.status_code == 403,
              str(pry.status_code))

    # ---- query parameters the worksheet names ---------------------------
    own_id = farmer["user"]["id"]
    staff_token = login("staff@example.com")["token"]

    as_owner = CLIENT.get(f"{API}/api/batches?farmer_id={own_id}",
                          headers=auth(farmer_token), timeout=20)
    check("a farmer may filter by its own id -> 200",
          as_owner.status_code == 200, str(as_owner.status_code))

    as_stranger = CLIENT.get(f"{API}/api/batches?farmer_id=999999",
                             headers=auth(farmer_token), timeout=20)
    check("a farmer may not filter by someone else -> 403",
          as_stranger.status_code == 403, str(as_stranger.status_code))

    as_staff = CLIENT.get(f"{API}/api/batches?farmer_id={own_id}",
                          headers=auth(staff_token), timeout=20)
    check("staff may filter by farmer_id -> 200",
          as_staff.status_code == 200, str(as_staff.status_code))
    check("the staff filter is honoured",
          as_staff.status_code == 200 and all(
              b.get("farmer_id") == own_id for b in as_staff.json().get("data", [])),
          str(as_staff.json().get("count")))

    today = _date.now().strftime("%Y-%m-%d")
    ranged = CLIENT.get(f"{API}/api/batches?start_date=2020-01-01&end_date={today}",
                        headers=auth(staff_token), timeout=20)
    check("date range accepted -> 200", ranged.status_code == 200, str(ranged.status_code))
    check("today's batch falls inside the window",
          ranged.status_code == 200 and ranged.json().get("count", 0) >= 1,
          str(ranged.json().get("count")))

    outside = CLIENT.get(f"{API}/api/batches?start_date=2099-01-01",
                         headers=auth(staff_token), timeout=20)
    check("an empty window is an empty list, not an error",
          outside.status_code == 200 and outside.json().get("count") == 0,
          str(outside.json().get("count")))

    bad_date = CLIENT.get(f"{API}/api/batches?start_date=01-01-2020",
                          headers=auth(staff_token), timeout=20)
    check("malformed date -> 400", bad_date.status_code == 400, str(bad_date.status_code))

    backwards = CLIENT.get(f"{API}/api/batches?start_date=2030-01-01&end_date=2020-01-01",
                           headers=auth(staff_token), timeout=20)
    check("start_date after end_date -> 400",
          backwards.status_code == 400, str(backwards.status_code))

    print("\n16. Activity 3 - PostgreSQL persistence (Part E)")

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON kcu.constraint_name = tc.constraint_name
         AND kcu.table_schema = tc.table_schema
        WHERE tc.table_name = 'users' AND tc.constraint_type = 'FOREIGN KEY'
    """)
    user_fks = {row[0] for row in cur.fetchall()}
    check("users.role_id is a foreign key onto roles",
          "role_id" in user_fks, str(sorted(user_fks)))

    cur.execute("""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON kcu.constraint_name = tc.constraint_name
         AND kcu.table_schema = tc.table_schema
        WHERE tc.table_name = 'batches' AND tc.constraint_type = 'FOREIGN KEY'
    """)
    batch_fks = {row[0] for row in cur.fetchall()}
    check("batches.farmer_id is a foreign key onto users",
          "farmer_id" in batch_fks, str(sorted(batch_fks)))
    check("the old batches.user_id column is gone", "user_id" not in batch_fks,
          str(sorted(batch_fks)))

    cur.execute("""
        SELECT indisunique
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = i.indkey[0]
        WHERE c.relname = 'users' AND a.attname = 'email'
    """)
    uniq = cur.fetchall()
    check("users.email is unique at the database level",
          bool(uniq) and bool(uniq[0][0]))

    cur.execute("SELECT COUNT(*) FROM users WHERE role_id IS NULL")
    check("every account is linked to the roles table", cur.fetchone()[0] == 0)

    # The atomicity Part E asks for is observable as a batch that was opened by
    # a classification always having that classification attached to it.
    cur.execute("""
        SELECT b.id, COUNT(c.id)
        FROM batches b
        JOIN classification_records c ON c.batch_id = b.id
        WHERE b.name = %s
        GROUP BY b.id
    """, ("IT110 Demo Batch",))
    linked = cur.fetchall()
    check("classify opened its batch with the record attached",
          len(linked) >= 1, f"{len(linked)} batches")
    check("that batch was not left empty",
          all(count >= 1 for _, count in linked), str(linked))

    cur.close()
    conn.close()

    print(f"\n{'=' * 46}\n{PASSED} passed, {FAILED} failed")
    sys.exit(1 if FAILED else 0)


if __name__ == "__main__":
    main()
