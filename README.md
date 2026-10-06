# Smart Office Queue & Token Management System

A full-stack office queue manager: visitors take a numbered token for a department and watch their live position; staff call, complete, skip and transfer tokens; admins pause departments and see statistics.

**Stack:** Flutter (Material 3, Provider) · Go (REST + JWT, layered) · PostgreSQL

> **Status of this code.** The Go backend was compiled, unit-tested (16 tests) and exercised end to end against a real PostgreSQL 16 (36 API checks, `backend/scripts/smoke_test.py`). The Flutter app was written carefully but **could not be compiled in the authoring environment** - run `flutter analyze` first and fix any small issue it reports (see "Known limitations").

## 1. Features

**Visitor** - home, department selection (live waiting count / paused status), token generation (normal or priority), token details with **live queue position and estimated wait**, cancel, follow a transfer to the new token, token history.
**Staff** - own-department desk: now serving, waiting queue, *Call next*, *Complete*, *No show*, *Transfer*, token details, statistics.
**Admin** - everything staff can do for any department, plus pause/resume departments, an overall dashboard, department-wise statistics and a chart.

## 2. Architecture

```
 Flutter app                                   Go API                                   PostgreSQL
┌───────────────────────┐   HTTP/JSON    ┌──────────────────────────────┐   pgx    ┌───────────────┐
│ screens / widgets     │  (poll 5 s)    │ handler  (routes, JWT, JSON) │          │ departments   │
│   ▲                   │ ─────────────► │    ▼                         │ ───────► │ users         │
│ providers (Provider)  │                │ service  (ALL queue rules)   │          │ tokens        │
│   ▲                   │ ◄───────────── │    ▼                         │ ◄─────── │ queue_events  │
│ repositories          │                │ store.Repo (interface)       │          └───────────────┘
│   ▲                   │                │    ▼                         │
│ ApiClient (http)      │                │ store/postgres (SQL, tx)     │
└───────────────────────┘                └──────────────────────────────┘
```
The backend is the **single source of truth**. Flutter never computes positions, ETAs or ordering; it renders what the API returns.

## 3. Technology stack
Flutter 3.22+ / Dart 3.4+, `provider`, `http`, `shared_preferences` · Go 1.22+, `net/http` (1.22 routing), `pgx/v5`, `golang-jwt/v5`, `bcrypt` · PostgreSQL 13+ (uses `gen_random_uuid()`).

## 4. Database schema
Full SQL: `database/schema.sql` (identical to `backend/migrations/*.up.sql`; the server applies migrations automatically at startup). All primary keys are **UUID**.

| table | key columns |
|---|---|
| `departments` | name, code (IT/HR/ACC/ADM), `is_paused`, `last_token_seq` (per-department counter), `default_service_minutes`, `sort_order` |
| `users` | name, email (unique, case-insensitive), `password_hash` (bcrypt), `role` STAFF/ADMIN, `department_id` FK |
| `tokens` | `token_number`, `department_id` FK, `priority` 0/1, `status`, `no_show_count`, `sequence_no`, `queue_entered_at`, `created_at`, `called_at`, `completed_at`, `cancelled_at`, `transferred_from_token_id` FK→tokens |
| `queue_events` | `token_id` FK, `event_type`, `metadata` JSONB, `created_at` (audit / transfer history) |

Notable constraints and indexes: `idx_tokens_queue_order (department_id, status, priority DESC, queue_entered_at, sequence_no)` serves exactly the queue ordering; **`uq_one_serving_per_department`** (partial unique index `WHERE status='SERVING'`) makes it impossible for the database to hold two serving tokens in one department; CHECK constraints on status/priority/role. Extra: `queue_entered_at` (explained below) and `sequence_no` (tie-breaker) are additions to the suggested fields.

## 5-6. Prerequisites and PostgreSQL setup
Install Go 1.22+, Flutter, PostgreSQL 13+.

```bash
# Option A - Docker
docker compose up -d                       # PostgreSQL on :5432 (matches .env.example)

# Option B - local PostgreSQL
psql -U postgres -c "CREATE USER queue_user WITH PASSWORD 'change_me'"
psql -U postgres -c "CREATE DATABASE smart_office_queue OWNER queue_user"
```
No manual migration step: the server creates the tables and the four departments on first start.

## 7. Environment variables (`backend/.env.example`)
| variable | meaning |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (required) |
| `JWT_SECRET` | signing secret, ≥16 chars (required) - `openssl rand -hex 32` |
| `JWT_TTL_HOURS` | token lifetime, default 12 |
| `PORT` | default 8080 |
| `CORS_ALLOWED_ORIGINS` | `*` for dev, or a comma-separated origin list |
| `SEED_ON_START` / `SEED_PASSWORD` | create the demo users once, with this password |

`cp backend/.env.example backend/.env` and edit. `.env` is git-ignored; no secret is in the source.

## 8. Run the backend
```bash
cd backend
cp .env.example .env          # edit DATABASE_URL / JWT_SECRET
go mod tidy                   # downloads dependencies, creates go.sum
go run ./cmd/server           # http://localhost:8080  (GET /api/health)
go test ./...                 # queue-rule tests (no database needed)
```
Optional end-to-end check against the running server (fresh DB): `SEED_PASSWORD=Demo@12345 python3 scripts/smoke_test.py`.

## 9. Run the frontend
```bash
cd frontend
flutter create . --platforms=web,android,ios   # one-time: generates platform folders (keeps lib/, pubspec.yaml)
flutter pub get
flutter analyze
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
# Android emulator: --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

## 10. Default test credentials
Created at first start when `SEED_ON_START=true`. Password = your `SEED_PASSWORD` (`Demo@12345` in `.env.example`; demo only).

| role | email | department |
|---|---|---|
| Admin | `admin@smartoffice.local` | all |
| Staff | `it.staff@smartoffice.local` | IT Support |
| Staff | `hr.staff@smartoffice.local` | HR |
| Staff | `accounts.staff@smartoffice.local` | Accounts |
| Staff | `admin.staff@smartoffice.local` | Administration |

Visitors need no account.

## 11. API
All errors: `{"error": {"code": "department_paused", "message": "..."}}`. IDs are UUIDs. 🔓 public · 👤 staff/admin JWT (`Authorization: Bearer …`, staff limited to own department) · 👑 admin.

| method & path | who | notes |
|---|---|---|
| `POST /api/auth/login` | 🔓 | `{email,password}` → `{token,expires_at,user}` |
| `GET /api/departments` · `GET /api/departments/{id}` | 🔓 | waiting count, serving token, paused, avg service time |
| `POST /api/departments/{id}/pause` · `/resume` | 👑 | idempotent |
| `POST /api/tokens` | 🔓 | `{department_id, priority:"NORMAL"\|"PRIORITY"}` → 201 · 409 `department_paused` |
| `GET /api/tokens/{id}` | 🔓 | live `queue_position`, `people_ahead`, `estimated_wait_minutes`, `events` history |
| `DELETE /api/tokens/{id}` · `POST /api/tokens/{id}/cancel` | 🔓 | WAITING tokens only |
| `GET /api/queues/{departmentId}` | 🔓 | serving token + ordered waiting list + stats |
| `POST /api/queues/{departmentId}/call-next` | 👤 | priority first, then FIFO |
| `POST /api/tokens/{id}/call` | 👤 | call a specific token - allowed only if it is the head of the queue |
| `POST /api/tokens/{id}/complete` · `/no-show` | 👤 | token must be SERVING |
| `POST /api/tokens/{id}/transfer` | 👤 | `{target_department_id}` → `{old_token,new_token}` |
| `GET /api/dashboard` | 👑 | totals + per-department statistics |
| `GET /api/dashboard/{departmentId}` | 👤 | one department |

Status codes: 400 validation / invalid id / invalid transfer · 401 · 403 · 404 (unknown id, `queue_empty`) · 409 (`department_paused`, `serving_in_progress`, `token_serving`, `token_completed`, `token_cancelled`, `invalid_state`, `not_next_in_queue`) · 500 (details logged, never leaked).

## 12. Queue logic explained (interview notes)

**One ordering rule, used everywhere:** `ORDER BY priority DESC, queue_entered_at ASC, sequence_no ASC` over tokens with status `WAITING`.
- *Call next* = the first row. *Queue position* = 1 + how many waiting tokens sort before this one. *Estimated wait* = people ahead × average service time. All three use the same ordering, so they can never disagree.
- **Positions are never stored.** They are computed on every request, so they cannot go stale after a create / cancel / call / complete / no-show / transfer. The Flutter app polls every 5 s (simple and reliable; no WebSocket complexity).

**Priority:** a priority token sorts before normal ones (FIFO among priority tokens). It only affects `WAITING` tokens - a `SERVING` token is never touched, and *Call next* refuses (409) while someone is being served. Two protections: an application check under a lock, and the partial unique index in the database.

**No-show:** 1st → `no_show_count = 1`, status back to `WAITING`, `queue_entered_at = now` ⇒ the token sorts after everyone already waiting in its tier ("end of the queue"). 2nd → status `CANCELLED`; cancelled tokens are not `WAITING`, so they are never eligible. *Design decision:* a priority token that no-shows goes to the end of the **priority tier**, so it still sorts ahead of normal tokens.

**Complete:** `SERVING → COMPLETED`, stores `completed_at`; service time = `completed_at − called_at`.

**Cancel:** only `WAITING` tokens; serving/completed/cancelled get a specific 409.

**Transfer:** only `WAITING` tokens. The original token becomes `TRANSFERRED` (kept for history); a **new** token with the next number of the target department (e.g. `HR-004`) is created, linked by `transferred_from_token_id`, keeping its priority; its `queue_entered_at` is the transfer time. Paused target ⇒ 409. Events `TRANSFERRED_OUT/IN` store the history. All in one transaction.

**Pause:** blocks *new* tokens and incoming transfers; existing tokens stay queued and can still be served.

**Estimated wait:** `ahead × avg_service_minutes`. The average is the real mean of `completed_at − called_at` once the department has ≥5 completions (minimum 1 min), otherwise the department default (5 min). Priority is respected because "ahead" comes from the ordered queue (a priority token with nobody priority-ahead shows 0).

**Concurrency / transactions:** every queue-changing operation runs in a transaction and first locks the department row (`SELECT … FOR UPDATE`). This serialises changes per department: token numbers (`IT-001…`, from an atomic counter) never duplicate (tested with 40 parallel requests), and two staff pressing *Call next* cannot both succeed. Transfers lock both departments in sorted order to avoid deadlocks.

**Security:** bcrypt passwords, HS256 JWT (algorithm pinned, expiry checked), role middleware + per-department authorization in the service, parameterised SQL only, strict JSON decoding, secrets only from environment. Token IDs are random UUIDs, so a visitor can only cancel a token whose id they hold.

## 13. Important files
| file | why it matters |
|---|---|
| `backend/internal/service/queue.go` | **all business rules** (read this first) |
| `backend/internal/service/queue_test.go` + `fake_repo_test.go` | rule tests on an in-memory store |
| `backend/internal/store/postgres/postgres.go` | the SQL: ordering, position, stats, locking |
| `backend/internal/store/store.go` | repository interface (what makes the service testable) |
| `backend/internal/handler/*` | routes, auth middleware, error→HTTP mapping |
| `backend/internal/auth/auth.go` | bcrypt + JWT + login |
| `backend/migrations/001_init.up.sql` | schema, indexes, constraints |
| `frontend/lib/services/api_client.dart` | the only place that does HTTP |
| `frontend/lib/providers/*` | state + polling (`utils/poller.dart`) |
| `frontend/lib/screens/*` | the nine screens |

## 14. Screenshots
Add images to `screenshots/` after running the app (folder is empty in this delivery).

## 15. Known limitations
- **Flutter code is not compile-verified** (see top). Run `flutter analyze`; likely issues are deprecation warnings (`withOpacity`, `DropdownButtonFormField.value`) on very new Flutter versions.
- Live updates use 5-second polling, not push.
- JWT is kept in `shared_preferences` (use secure storage in production); no refresh tokens or password change/reset UI.
- Token counters never reset (no daily reset); statistics are all-time, not per day.
- Backend tests cover rules on an in-memory fake store; SQL is covered by `scripts/smoke_test.py`, not Go integration tests. No Flutter widget tests beyond small unit tests.
- Any visitor with a token id can cancel it (ids are unguessable UUIDs, but there is no further visitor auth).
