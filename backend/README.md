# Backend (Go)

Layers: `cmd/server` (wiring) → `internal/handler` (HTTP) → `internal/service` (business rules) → `internal/store` (interface) → `internal/store/postgres` (SQL). `internal/domain` holds types and business errors, `internal/auth` JWT/bcrypt, `internal/db` the migration runner, `migrations/` the embedded SQL.

```bash
cp .env.example .env     # set DATABASE_URL, JWT_SECRET, SEED_PASSWORD
go mod tidy
go run ./cmd/server
go test ./...            # unit tests for the queue rules (no DB needed)
python3 scripts/smoke_test.py   # end-to-end against the running API (fresh DB)
```
See the root `README.md` for the API reference and queue-logic explanation.
