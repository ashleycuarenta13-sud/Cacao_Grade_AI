# REST API contract

The API as Activity 3, Part D specifies it, and as it is actually implemented.
`backend/e2e_test.py` asserts every row below - section numbers in brackets.

Base URL: `http://127.0.0.1:8000` locally, `https://<service>` on Cloud Run.
Every authenticated route takes `Authorization: Bearer <JWT>`.

## Contract worksheet

| # | Use case | Method | Endpoint | Auth / role | Request | Response / status | Check |
|---|---|---|---|---|---|---|---|
| 1 | Log in | POST | `/api/auth/login` | Public | `{email, password}` | `200 {token, user}` / `401` | [4] |
| 2 | Get current profile | GET | `/api/auth/profile` | Any authenticated role | JWT header | `200 {user}` / `401` | [14] |
| 3 | Update profile | PUT | `/api/auth/profile` | Any authenticated role | `{full_name, contact, email}` | `200 {user}` / `400` | [14] |
| 4 | Submit classification | POST | `/api/classify` | `farmer`, `staff`, `admin` | multipart `file` + `batch_name` + `notes` | `200 {class, confidence, quality_notes, recommendation}` / `422` | [5][10] |
| 5 | List batch history | GET | `/api/batches` | Any authenticated role, filtered by role | `?farmer_id=&start_date=&end_date=` | `200 [batch]` / `401` | [7][15] |
| 6 | Get batch detail | GET | `/api/batches/{id}` | Owner, `staff`, `admin` | path `id` | `200 {batch, records}` / `404` | [15] |

### 1. `POST /api/auth/login`

```jsonc
// request
{ "email": "rico@example.com", "password": "password123" }

// 200
{ "status": "success", "token": "<jwt>", "user": { "id": 3, "full_name": "...",
  "email": "...", "role": "farmer" } }

// 401
{ "detail": "Incorrect email or password." }
```

### 2. `GET /api/auth/profile`

```jsonc
// 200
{ "status": "success", "user": { "id": 3, "full_name": "...", "email": "...",
  "role": "farmer", "contact": "", "created_at": "..." } }

// 401  no/expired/revoked token
```

`contact` is the "contact info" column the worksheet's request data names.

### 3. `PUT /api/auth/profile`

```jsonc
// any subset - a field left out is left alone, never blanked
{ "full_name": "Rico D. Respecia", "contact": "+63 917 000 1234" }

// 200  the refreshed user
// 400  empty name, or an email another account already holds
```

The body has **no `role` field on purpose.** Re-pointing an account is
`PATCH /api/admin/users/{id}` and an administrator's call alone, so a
self-service edit cannot be used to escalate. [14] asserts this.

### 4. `POST /api/classify`

```
Content-Type: multipart/form-data
file        - jpg/png, <= 10 MB
batch_name  - optional, <= 80 chars; opening one is what makes it transactional
notes       - optional, <= 500 chars
```

| Status | Meaning | Client's offline queue |
|---|---|---|
| `200` | `{status, id, batch_id, filename, predicted_class, confidence, quality_notes, recommendation, image_url, engine}` | — |
| `401` / `403` | Not logged in / role may not classify | Not queued |
| **`422`** | Photo is not a usable image: wrong type, empty, over 10 MB, or undecodable | **Not queued** - replaying identical bytes cannot help |
| **`502`** | CNN service answered with an error or a malformed payload | **Queued** - transient |
| **`503`** | CNN service unreachable | **Queued** - transient |

The 422/502/503 split is the contract the client's retry policy keys off
(`lib/core/pending_uploads.dart`). Part D states 422 as this endpoint's single
failure code; the 5xx codes are the document's "network downtime during upload"
case from Part I.

### 5. `GET /api/batches`

Query parameters, as the worksheet names them:

| Parameter | Effect |
|---|---|
| `farmer_id` | Only that farmer's batches. Shared-history roles (`staff`, `admin`, `buyer`, `extension_worker`) may use it; a farmer may only pass its own id, otherwise `403`. |
| `start_date` | Inclusive lower bound, `YYYY-MM-DD`. |
| `end_date` | Inclusive upper bound, `YYYY-MM-DD`. |

A farmer is pinned to its own rows regardless of what it passes. Malformed or
backwards date ranges answer `400`.

```jsonc
// 200
{ "status": "success", "count": 15, "scope": "all",
  "filters": { "farmer_id": null, "start_date": "2026-10-01", "end_date": "2026-10-15" },
  "data": [ { "id": 27, "farmer_id": 3, "name": "...", "status": "Classified",
              "farmer": "...", "record_count": 1, "latest_stage": "well_fermented",
              "latest_confidence": 0.34, "latest_filename": "..." } ] }
```

`farmer_id` (not `user_id`) is Part E's column name. See [15].

### 6. `GET /api/batches/{id}`

```jsonc
// 200
{ "status": "success",
  "batch": { "id": 27, "farmer_id": 3, "name": "...", "record_count": 1,
             "records": [ { "id": 41, "filename": "...",
                            "predicted_class": "well_fermented",
                            "confidence": 0.34, "recommendation": "...",
                            "created_at": "...", "notes": "...",
                            "quality_notes": "...", "image_url": "/uploads/...",
                            "engine": "heuristic" } ] } }

// 403  another farmer's batch
// 404  no such id
```

## Endpoints outside the worksheet

These come from Activity 2 and remain in use.

| Method | Endpoint | Role | Purpose |
|---|---|---|---|
| POST | `/api/auth/register` | Public | Creates an account as `farmer` |
| GET | `/api/auth/me` | Any authenticated | Same payload as `GET /api/auth/profile`, kept for the existing client |
| POST | `/api/auth/logout` | Any authenticated | Revokes the JWT through its `jti` |
| GET | `/api/history` | Any authenticated | Flat classification list |
| POST | `/api/batches` | `farmer`, `staff`, `admin` | Open an empty batch before a photo exists |
| DELETE | `/api/batches/{id}` | `staff`, `admin` any; `farmer` own only | `403` for `buyer` / `extension_worker` |
| GET | `/api/trends` | Any authenticated | Aggregates for the dashboard |
| GET | `/api/roles` | Any authenticated | The five actors |
| GET | `/api/admin/users` | `admin` | User table for the admin console |
| PATCH | `/api/admin/users/{id}` | `admin` | Assign a role; an admin may not demote itself |
| GET | `/uploads/{name}` | Public | Serves a stored photo (stand-in for a bucket URL) |
| GET | `/health`, `/api/health` | Public | Liveness + database check |

## Status-code rules

- **Authentication** failures are `401`; **authorization** failures are `403`.
  The check runs on the *actor* before the row, so a read-only role gets `403`
  even for an id that does not exist.
- **Profile and batch-name** validation is `400` (Part D's stated code).
- **Classification input** is `422` (Part D's stated code).
- **Unknown id** is `404`.
- **CNN service trouble** is `502` / `503`, never `4xx`, so the client can tell
  "retry this later" from "this will never work".
