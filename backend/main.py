import os
import re
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
import httpx

from database import (
    init_db,
    init_roles,
    save_classification,
    save_batch_with_record,
    get_all_classifications,
    row_to_record,
    create_batch,
    list_batches,
    get_batch_detail,
    get_batch_owner,
    delete_batch,
    fermentation_trends,
    get_roles
)
from auth import (
    AuthError,
    init_auth_db,
    create_user,
    authenticate,
    create_session,
    get_user_by_token,
    delete_session,
    extract_bearer_token,
    purge_expired_sessions,
    get_profile,
    update_user_profile,
    list_users,
    update_user_role
)

app = FastAPI(
    title="Cacao Grade AI Backend API",
    description="Backend API for Cacao Grade AI",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Activity 2, Part A - "HTTPS for all client-server and server-service
# communication". Both hops are configurable, so the same code serves the
# plaintext coursework setup and the TLS one:
#
#   set CACAO_CNN_URL=https://127.0.0.1:8001/predict
#
# and the self-signed certificate from make_cert.py is trusted automatically.
CERT_DIR = Path(__file__).resolve().parent.parent / "certs"

# Part F's `CNN_SERVICE_URL` is the document's spelling of the same setting;
# `CACAO_CNN_URL` is kept as well because `run.py --ssl` sets it.
CNN_SERVICE_URL = (
    os.getenv("CACAO_CNN_URL")
    or os.getenv("CNN_SERVICE_URL")
    or "http://127.0.0.1:8001/predict"
)


def _cnn_verify():
    """Trust the certificate that make_cert.py wrote, for the HTTPS hop.

    A plaintext hop needs no CA, so it stays on httpx's default. Returning a
    path rather than False keeps the certificate actually checked - disabling
    verification would give the encryption but none of the authentication.
    """
    if not CNN_SERVICE_URL.startswith("https://"):
        return True

    override = os.getenv("CACAO_CNN_CA")

    if override:
        return override

    local = CERT_DIR / "cert.pem"
    return str(local) if local.exists() else True

# Local stand-in for the Google Cloud Storage bucket in the activity document:
# every uploaded cut-test photo is kept here and served back through
# GET /uploads/{name}.
UPLOAD_DIR = Path(__file__).resolve().parent / "uploads"

# The five actors the activity document lists. They are rows in the `roles`
# table (seeded by database.seed_roles); this set is only the guard used at
# the API boundary.
KNOWN_ROLES = {"farmer", "staff", "buyer", "extension_worker", "admin"}

# Roles allowed to submit a cut-test photo (Activity 2, Part D, step 4).
# A buyer buys and an extension worker monitors - neither grades cacao, so
# neither may POST /api/classify.
CLASSIFY_ROLES = {"farmer", "staff", "admin"}

# Roles that review every batch rather than only their own. Buyers read the
# quality history of what they purchase; extension workers monitor the
# accounts of the farmers they advise.
SHARED_HISTORY_ROLES = {"staff", "admin", "buyer", "extension_worker"}

# Only these roles may remove somebody else's batch. Buyer and extension
# worker are read-only on /api/batches/{id}.
DELETE_BATCH_ROLES = {"staff", "admin"}

# Buyer and extension worker hold a read-only interest in batches, so they
# are refused before the row is even looked up.
READ_ONLY_BATCH_ROLES = {"buyer", "extension_worker"}

# Admin-only, because it re-points somebody's access.
ASSIGN_ROLE_ROLES = {"admin"}

# Accepts the stored slug *and* the actor names the activity document uses,
# so an administrator can send either "buyer" or "Cooperative Staff".
ROLE_ALIASES = {
    "farmer": "farmer",
    "staff": "staff",
    "cooperative_staff": "staff",
    "co_op_staff": "staff",
    "coop_staff": "staff",
    "buyer": "buyer",
    "cacao_buyer": "buyer",
    "extension_worker": "extension_worker",
    "agricultural_extension_worker": "extension_worker",
    "extensionist": "extension_worker",
    "admin": "admin",
    "administrator": "admin",
}


def _normalise_role(raw: str) -> str | None:
    """`'Cooperative Staff'` -> `'staff'`; `'astronaut'` -> None."""
    key = re.sub(r"[^a-z0-9]+", "_", raw.strip().lower()).strip("_")
    return ROLE_ALIASES.get(key)

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png"}
MAX_IMAGE_BYTES = 10 * 1024 * 1024

# Clients (dili giserve niining backend; API ra ang giserve):
#   frontend/ -> FLUTTER APP (aka ang web/mobile client)
#   RUN: cd frontend && flutter run -d chrome


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=1, max_length=128)


# Business logic layer (Activity 2, Part A): the quality note and the
# actionable recommendation are generated on the server from the predicted
# class, so both clients get identical wording.
QUALITY_NOTES = {
    "unfermented": (
        "Cut surface is pale, whitish or violet-grey. The beans still smell "
        "acidic and astringent."
    ),
    "partially_fermented": (
        "Cut surface is tan to light brown with an uneven brown centre. "
        "Fermentation is not yet uniform through the bean."
    ),
    "well_fermented": (
        "Cut surface is an even rich brown with no white streaks. Beans smell "
        "chocolatey and the nibs snap cleanly."
    ),
    "over_fermented": (
        "Cut surface is very dark brown to black, sometimes cracked or "
        "mouldy, with a sour or alcoholic odour."
    ),
}

RECOMMENDATIONS = {
    "unfermented": "Dili pa fermented. Kinahanglan pa kining ipa-ferment pag-usab.",
    "partially_fermented": "Kulang pa ang fermentation para maabot ang husto nga quality.",
    "well_fermented": "Well-fermented cacao bean. Maayo para sa premium chocolate production.",
    "over_fermented": "Sobra na ang fermentation. Mahimong makaapekto sa flavor quality."
}


def _normalise_class(label) -> str:
    """Maps any stage spelling ('well-fermented', 'Well Fermented') onto the
    underscore keys used by the business-logic tables."""
    key = str(label or "").strip().lower().replace("-", "_").replace(" ", "_")
    return key if key in RECOMMENDATIONS else str(label or "")


def _safe_suffix(filename: str, content_type: str = "") -> str:
    """Extension for the stored photo, decided by what the file actually is."""
    by_type = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
    }

    suffix = by_type.get(content_type, "")

    if suffix:
        return suffix

    suffix = Path(filename or "").suffix.lower()
    return suffix if suffix in {".jpg", ".jpeg", ".png"} else ".jpg"


def _require_user(authorization: str) -> dict:
    """Verifies the session token (Activity 2, Part D, step 4)."""
    user = get_user_by_token(extract_bearer_token(authorization))

    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Session expired or not logged in."
        )

    return user


@app.on_event("startup")
def startup_event():
    # `roles` has to exist before `users` can declare `role_id` onto it, and
    # `users` before `batches` / `classification_records` can reference it.
    init_roles()
    init_auth_db()
    init_db()
    purge_expired_sessions()


@app.get("/health")
@app.get("/api/health")
def health_check():
    try:
        from database import get_connection

        conn = get_connection()
        conn.close()
        database_connected = True
    except Exception:
        database_connected = False

    return {
        "status": "success" if database_connected else "error",
        "backend": "running",
        "database": "connected" if database_connected else "disconnected",
        "cnn_service": CNN_SERVICE_URL
    }


@app.get("/api/database-test")
def database_test():
    return {
        "status": "success",
        "message": "Backend is connected to PostgreSQL!"
    }


@app.post("/api/classify")
async def classify_image(
    file: UploadFile = File(...),
    batch_name: str = Form(default=""),
    notes: str = Form(default=""),
    authorization: str = Header(default=""),
):
    """Activity 2, Part D end to end.

    Step 4  verify the session token and the caller's role
    Step 5  validate the photo server-side and store it
    Step 6  forward the photo to the CNN inference service
    Step 7  read back the predicted class and its confidence
    Step 8  generate the quality note/recommendation and persist the record
    Step 9  answer with the classification payload
    """
    # Step 4 - authentication + role check.
    user = get_user_by_token(extract_bearer_token(authorization))

    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Session expired or not logged in."
        )

    if user["role"] not in CLASSIFY_ROLES:
        raise HTTPException(
            status_code=403,
            detail="Only farmers and cooperative staff can submit cut-test photos."
        )

    # Step 5 - server-side validation, then keep the photo.
    #
    # Activity 3, Part D gives POST /api/classify a single failure code: 422.
    # A 4xx here is always permanent - replaying the same bytes cannot fix a
    # wrong file type or an oversized file - which is exactly the property the
    # client's offline queue keys off, so 422 is treated as non-retryable.
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=422,
            detail="Only JPG and PNG images are allowed."
        )

    image_bytes = await file.read()

    if not image_bytes:
        raise HTTPException(
            status_code=422,
            detail="The uploaded image is empty."
        )

    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=422,
            detail="Image size must not exceed 10MB."
        )

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    stored_name = f"{uuid.uuid4().hex}{_safe_suffix(file.filename, file.content_type)}"
    (UPLOAD_DIR / stored_name).write_bytes(image_bytes)
    image_url = f"/uploads/{stored_name}"

    # Steps 6-7 - CNN inference service.
    try:
        async with httpx.AsyncClient(
            timeout=30.0, verify=_cnn_verify()
        ) as client:
            response = await client.post(
                CNN_SERVICE_URL,
                files={
                    "file": (
                        file.filename,
                        image_bytes,
                        file.content_type
                    )
                }
            )
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=503,
            detail=f"CNN service is unavailable: {str(e)}"
        )

    if response.status_code != 200:
        # A 4xx here means the photo itself could not be read, so replaying the
        # same bytes would never help - report it as a client error. A 5xx is
        # the inference service failing, which is transient and worth retrying.
        # Part E of the document depends on the client being able to tell those
        # two apart: only the second belongs in the pending queue.
        if 400 <= response.status_code < 500:
            detail = "CNN service could not read the image."
            try:
                detail = response.json().get("detail", detail)
            except Exception:
                pass
            raise HTTPException(status_code=422, detail=detail)

        raise HTTPException(
            status_code=502,
            detail="CNN service returned an error."
        )

    cnn_result = response.json()

    # The model may legitimately not be trained yet.
    if cnn_result.get("status") == "waiting":
        return {
            "status": "waiting",
            "message": "CNN model is not trained yet.",
            "filename": file.filename,
            "image_url": image_url
        }

    predicted_class = _normalise_class(cnn_result.get("predicted_class"))
    confidence = cnn_result.get("confidence")

    if not predicted_class or confidence is None:
        raise HTTPException(
            status_code=502,
            detail="Invalid response from CNN service."
        )

    # Step 8 - business logic + persistence.
    quality_notes = QUALITY_NOTES.get(predicted_class)

    recommendation = RECOMMENDATIONS.get(
        predicted_class,
        "No recommendation available."
    )

    clean_name = batch_name.strip()[:80]
    clean_notes = notes.strip()[:500]

    # Every submission opens a batch, so Batch History lives in PostgreSQL
    # instead of on the device (Part A - /api/batches).
    #
    # Activity 3, Part E: *"the batch row and its first classification_records
    # row are inserted in one transaction."* A submission that named its batch
    # therefore goes through save_batch_with_record(), which commits both rows
    # together - a photo can never hang off a rolled-back batch, and a batch can
    # never be left empty because its record failed. Unnamed submissions only
    # ever write the one record, so there is no pair to keep atomic.
    record_id = None
    batch_id = None

    if clean_name:
        saved = save_batch_with_record(
            farmer_id=user["id"],
            batch_name=clean_name,
            batch_notes=clean_notes,
            filename=file.filename,
            label=predicted_class,
            confidence=confidence,
            recommendation=recommendation,
            record_notes=clean_notes or None,
            quality_notes=quality_notes,
            image_url=image_url,
            engine=cnn_result.get("engine")
        )
        record_id = saved["id"]
        batch_id = saved["batch_id"]

    else:
        record_id = save_classification(
            filename=file.filename,
            label=predicted_class,
            confidence=confidence,
            recommendation=recommendation,
            user_id=user["id"],
            batch_name=None,
            notes=clean_notes or None,
            quality_notes=quality_notes,
            image_url=image_url,
            engine=cnn_result.get("engine")
        )

    # Step 9 - the payload the Flutter client renders.
    return {
        "status": "success",
        "id": record_id,
        "batch_id": batch_id,
        "filename": file.filename,
        "predicted_class": predicted_class,
        "confidence": confidence,
        "quality_notes": quality_notes,
        "recommendation": recommendation,
        "image_url": image_url,
        "engine": cnn_result.get("engine")
    }


@app.get("/uploads/{name}")
def stored_image(name: str):
    """Serves a stored cut-test photo (stand-in for a storage-bucket URL)."""
    target = UPLOAD_DIR / name

    if not name or target.parent != UPLOAD_DIR or not target.is_file():
        raise HTTPException(status_code=404, detail="Image not found.")

    return FileResponse(target)


@app.get("/api/history")
def classification_history(authorization: str = Header(default="")):
    """Farmers read their own batch history; staff and admins read every record."""
    user = _require_user(authorization)

    shared = user["role"] in SHARED_HISTORY_ROLES
    rows = get_all_classifications(None if shared else user["id"])

    return {
        "status": "success",
        "count": len(rows),
        "scope": "all" if shared else "own",
        "data": [row_to_record(row) for row in rows]
    }


# --------------------------------------------------------------- /api/batches

class BatchRequest(BaseModel):
    name: str = Field(default="", max_length=80)
    notes: str = Field(default="", max_length=500)


@app.get("/api/batches")
def batches(
    authorization: str = Header(default=""),
    farmer_id: int | None = Query(
        default=None,
        description="Only this farmer's batches. A caller outside SHARED_HISTORY_ROLES may not use it."
    ),
    start_date: str | None = Query(
        default=None,
        description="Inclusive lower bound, YYYY-MM-DD."
    ),
    end_date: str | None = Query(
        default=None,
        description="Inclusive upper bound, YYYY-MM-DD."
    ),
):
    """Activity 3, Part D - `GET /api/batches`.

    The worksheet's contract is *"`farmer_id` and date range as query
    parameters"*, so the two optional filters are accepted here. Which of them
    a caller may actually use is decided by role before the query runs:

      * farmers may only ever see their own rows, whatever they ask for
      * staff/admin/buyer/extension_worker share the history and may narrow it
        to a farmer or to a date window
    """
    user = _require_user(authorization)

    shared = user["role"] in SHARED_HISTORY_ROLES

    if farmer_id is not None and not shared and farmer_id != user["id"]:
        raise HTTPException(
            status_code=403,
            detail="You may only filter by your own batches."
        )

    # An unshared role is pinned to its own id no matter what it passed in,
    # except that naming its own id is harmless and simply matches anyway.
    effective_farmer = (
        farmer_id if shared or farmer_id == user["id"] else user["id"]
    )

    for label, value in (("start_date", start_date), ("end_date", end_date)):
        if value:
            try:
                datetime.strptime(value, "%Y-%m-%d")
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail=f"{label} must be formatted YYYY-MM-DD."
                )

    if start_date and end_date and start_date > end_date:
        raise HTTPException(
            status_code=400,
            detail="start_date must not be after end_date."
        )

    items = list_batches(
        farmer_id=effective_farmer,
        start_date=start_date,
        end_date=end_date
    )

    return {
        "status": "success",
        "count": len(items),
        "scope": "all" if shared else "own",
        "filters": {
            "farmer_id": effective_farmer,
            "start_date": start_date,
            "end_date": end_date
        },
        "data": items
    }


@app.get("/api/batches/{batch_id}")
def batch_detail(batch_id: int, authorization: str = Header(default="")):
    """Activity 3, Part D - `GET /api/batches/{id}`.

    Returns *one batch with its classification records*, so the client can open
    a detail view without issuing a second request per photo.
    """
    user = _require_user(authorization)

    batch = get_batch_detail(batch_id)

    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found.")

    shared = user["role"] in SHARED_HISTORY_ROLES

    if not shared and batch.get("farmer_id") != user["id"]:
        raise HTTPException(
            status_code=403,
            detail="You may only open your own batches."
        )

    return {"status": "success", "batch": batch}


@app.post("/api/batches")
def create_batch_endpoint(
    payload: BatchRequest,
    authorization: str = Header(default="")
):
    """Registers an empty batch before any photo is attached to it."""
    user = _require_user(authorization)

    if user["role"] not in CLASSIFY_ROLES:
        raise HTTPException(
            status_code=403,
            detail="Only farmers and cooperative staff can create batches."
        )

    name = payload.name.strip()

    if not name:
        raise HTTPException(
            status_code=400,
            detail="Please enter a batch name."
        )

    batch = create_batch(
        farmer_id=user["id"],
        name=name,
        notes=payload.notes.strip(),
        status="Pending"
    )

    return {"status": "success", "batch": batch}


@app.delete("/api/batches/{batch_id}")
def remove_batch(batch_id: int, authorization: str = Header(default="")):
    """Staff and admins may delete any batch; farmers may delete only their
    own. Buyer and extension worker are read-only."""
    user = _require_user(authorization)

    # Refused on the actor, not on the row: a read-only role gets a 403 even
    # when the batch id does not exist.
    if user["role"] in READ_ONLY_BATCH_ROLES:
        raise HTTPException(
            status_code=403,
            detail="Buyers and extension workers have read-only access to batches."
        )

    if user["role"] not in DELETE_BATCH_ROLES:
        owner = get_batch_owner(batch_id)

        if owner is None:
            raise HTTPException(status_code=404, detail="Batch not found.")

        if owner != user["id"]:
            raise HTTPException(
                status_code=403,
                detail="This batch belongs to another farmer."
            )

    if not delete_batch(batch_id):
        raise HTTPException(status_code=404, detail="Batch not found.")

    return {"status": "success", "message": "Batch deleted."}


@app.get("/api/trends")
def trends(authorization: str = Header(default="")):
    """Activity 2, Part A - business logic: aggregation of batch and
    fermentation trend data for the dashboard."""
    user = _require_user(authorization)

    shared = user["role"] in SHARED_HISTORY_ROLES
    data = fermentation_trends(None if shared else user["id"])

    return {
        "status": "success",
        "scope": "all" if shared else "own",
        **data
    }


def _public_user(user: dict) -> dict:
    return {
        "id": user["id"],
        "full_name": user["full_name"],
        "email": user["email"],
        "role": user["role"],
    }


@app.post("/api/auth/register")
def register(payload: RegisterRequest):
    try:
        user = create_user(
            full_name=payload.full_name,
            email=payload.email,
            password=payload.password
        )
        token = create_session(user["id"], user["role"])
    except AuthError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return {
        "status": "success",
        "message": "Account created successfully.",
        "token": token,
        "user": _public_user(user)
    }


@app.post("/api/auth/login")
def login(payload: LoginRequest):
    try:
        user = authenticate(payload.email, payload.password)
        token = create_session(user["id"], user["role"])
    except AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc))

    return {
        "status": "success",
        "message": "Logged in successfully.",
        "token": token,
        "user": _public_user(user)
    }


@app.get("/api/auth/me")
def me(authorization: str = Header(default="")):
    user = get_user_by_token(extract_bearer_token(authorization))

    if user is None:
        raise HTTPException(status_code=401, detail="Session expired or not logged in.")

    return {
        "status": "success",
        "user": _public_user(user)
    }


class ProfileUpdate(BaseModel):
    """The body Activity 3, Part D specifies for PUT /api/auth/profile.

    Every field is optional so a client can send only what it changed; a
    field left out is left alone rather than being blanked.
    """
    full_name: str | None = Field(default=None, max_length=120)
    contact: str | None = Field(default=None, max_length=60)
    email: str | None = Field(default=None, max_length=254)


@app.get("/api/auth/profile")
def read_profile(authorization: str = Header(default="")):
    """Activity 3, Part D - *Get current profile*.

    Contract: `200 + user JSON / 401`. Available to any authenticated role.
    """
    user = _require_user(authorization)
    profile = get_profile(user["id"])

    if profile is None:
        raise HTTPException(status_code=401, detail="Session expired or not logged in.")

    return {"status": "success", "user": profile}


@app.put("/api/auth/profile")
def write_profile(payload: ProfileUpdate, authorization: str = Header(default="")):
    """Activity 3, Part D - *Update profile*.

    Contract: `200 + updated user / 400`. Any authenticated role may edit its
    own name and contact details. The role is deliberately absent from the
    body - re-pointing an account is `PATCH /api/admin/users/{id}` and an
    administrator's call alone, so a self-service edit cannot be used to
    escalate.
    """
    user = _require_user(authorization)

    if payload.full_name is not None and not payload.full_name.strip():
        raise HTTPException(status_code=400, detail="The name cannot be empty.")

    try:
        updated = update_user_profile(
            user["id"],
            full_name=payload.full_name,
            contact=payload.contact,
            email=payload.email
        )
    except AuthError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    if updated is None:
        raise HTTPException(status_code=401, detail="Session expired or not logged in.")

    return {"status": "success", "user": updated}


@app.post("/api/auth/logout")
def logout(authorization: str = Header(default="")):
    delete_session(extract_bearer_token(authorization))

    return {
        "status": "success",
        "message": "Logged out."
    }


def _require_admin(authorization: str) -> dict:
    user = _require_user(authorization)

    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admins only.")

    return user


# --------------------------------------------------------------------- /roles

@app.get("/api/roles")
def list_roles(authorization: str = Header(default="")):
    """The five actors Activity 2, Part A, lists for the `roles` table.

    Authenticated only so the admin console can build its role dropdown from
    the same rows that guard the API, instead of a hard-coded copy.
    """
    _require_user(authorization)

    rows = get_roles()

    return {
        "status": "success",
        "count": len(rows),
        "data": [
            {"name": row["name"], "description": row["description"]}
            for row in rows
        ],
    }


class RoleRequest(BaseModel):
    role: str = Field(min_length=1, max_length=40)


@app.patch("/api/admin/users/{user_id}")
def admin_update_user_role(
    user_id: int,
    payload: RoleRequest,
    authorization: str = Header(default="")
):
    """Assigns one of the five documented roles (Activity 2, Part A).

    Self-assignment is refused: an administrator who demotes their own
    account locks everybody out of the admin console.
    """
    actor = _require_admin(authorization)

    role = _normalise_role(payload.role)

    if role is None or role not in KNOWN_ROLES:
        raise HTTPException(
            status_code=400,
            detail=(
                "Unknown role. Pick one of: "
                + ", ".join(sorted(KNOWN_ROLES)) + "."
            )
        )

    if user_id == actor["id"]:
        raise HTTPException(
            status_code=400,
            detail="You cannot change your own role."
        )

    try:
        updated = update_user_role(user_id, role)
    except AuthError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if updated is None:
        raise HTTPException(status_code=404, detail="No account with that id.")

    return {"status": "success", "user": updated}


@app.get("/api/admin/users")
def admin_list_users(authorization: str = Header(default="")):
    _require_admin(authorization)

    rows = list_users()

    users = []
    for row in rows:
        users.append({
            "id": row[0],
            "full_name": row[1],
            "email": row[2],
            "role": row[3],
            "created_at": row[4],
        })

    return {
        "status": "success",
        "count": len(users),
        "data": users
    }


@app.get("/")
def root():
    """Ang web frontend naa na sa frontend/ (Flutter app). API ra ang giserve niini."""
    return {
        "service": "CacaoGrade AI",
        "docs": "/docs",
        "health": "/health",
        "auth": "/api/auth/login",
        "endpoints": {
            "classify": "/api/classify",
            "history": "/api/history",
            "batches": "/api/batches",
            "trends": "/api/trends",
            "roles": "/api/roles",
            "admin_users": "/api/admin/users",
            "admin_set_role": "PATCH /api/admin/users/{id}",
        },
    }