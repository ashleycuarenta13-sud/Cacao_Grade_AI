# `database/`

The schema of record for CacaoGrade AI, kept as SQL rather than only as the
`CREATE TABLE` statements the backend runs at startup, so it can be read,
reviewed and applied on its own.

Activity 3, Part F puts `/database` in the project layout; Part E names the
tables it has to contain.

## Migrations

| File | What it does |
|---|---|
| `migrations/0001_init.sql` | Baseline: `roles`, `users`, `sessions`, `batches`, `classification_records`, plus the indexes the list endpoints filter on. |

Every statement is guarded with `IF NOT EXISTS` and the file runs inside a
single `BEGIN`/`COMMIT`, so replaying it against an existing database is safe.

```bash
psql "$DATABASE_URL" -f database/migrations/0001_init.sql
```

## Which part of the document it satisfies

Part E's table, in its own words:

| Resource | Document requirement | Where |
|---|---|---|
| Login/profile | `users` - PK `id`; unique `email`; **FK `role_id` → `roles.id`** | `users` table |
| Role checks | `roles` - PK `id` | `roles` table |
| Photo upload / new batch | `batches` - PK `id`; **FK `farmer_id` → `users.id`** | `batches` table |
| Classification result | `classification_records` - PK `id`; **FK `batch_id` → `batches.id`** | `classification_records` table |

> *"The batch row and its first `classification_records` row are inserted in
> one transaction."*

No single-statement constraint can span two tables, so that rule is enforced in
application code: `database.py::save_batch_with_record()` inserts both rows and
only then commits, rolling back the pair if either insert fails. Section 16 of
`backend/e2e_test.py` asserts the observable consequence - a batch opened by a
classification is never left empty.

`sessions` is not in the document's list. It holds one row per issued JWT so
that `jti` can be checked per request, which is what lets `POST /api/auth/logout`
revoke a bearer immediately instead of waiting for it to expire.

## The role registry

`roles` is seeded by both this migration and `database.py::init_roles()`, with
`ON CONFLICT (name) DO NOTHING`, so neither path can duplicate or overwrite a
row. The `can_submit_photos` / `can_review_batches` flags are the document's
Part A authorization model stored where a new environment cannot drift from
what the API enforces.
