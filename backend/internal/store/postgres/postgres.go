// Package postgres implements store.Repo on PostgreSQL using pgx.
// Every query is parameterised ($1, $2, ...) - no string concatenation of
// user input anywhere.
package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"smartoffice/internal/domain"
	"smartoffice/internal/store"
)

// querier is satisfied by both *pgxpool.Pool and pgx.Tx.
type querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type scanner interface{ Scan(dest ...any) error }

// Repo is the PostgreSQL store. pool is nil when the Repo is bound to a transaction.
type Repo struct {
	pool *pgxpool.Pool
	q    querier
}

var _ store.Repo = (*Repo)(nil)

func New(pool *pgxpool.Pool) *Repo { return &Repo{pool: pool, q: pool} }

// WithTx runs fn in a transaction (commit on nil, rollback on error/panic).
func (r *Repo) WithTx(ctx context.Context, fn func(store.Repo) error) error {
	if r.pool == nil { // already inside a transaction: join it
		return fn(r)
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }() // no-op after a successful commit
	if err := fn(&Repo{q: tx}); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}
	return nil
}

// mapErr converts driver errors to domain errors.
func mapErr(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrNotFound
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "uq_one_serving_per_department" {
		return domain.ErrServingInProgress // safety net behind the application-level check
	}
	return err
}

// ---------------------------------------------------------------- departments

const deptCols = `id::text, name, code, is_paused, default_service_minutes, created_at, updated_at`

func scanDept(s scanner) (*domain.Department, error) {
	var d domain.Department
	if err := s.Scan(&d.ID, &d.Name, &d.Code, &d.IsPaused, &d.DefaultServiceMinutes, &d.CreatedAt, &d.UpdatedAt); err != nil {
		return nil, mapErr(err)
	}
	return &d, nil
}

func (r *Repo) ListDepartments(ctx context.Context) ([]domain.Department, error) {
	rows, err := r.q.Query(ctx, `SELECT `+deptCols+` FROM departments ORDER BY sort_order, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Department{}
	for rows.Next() {
		d, err := scanDept(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

func (r *Repo) GetDepartment(ctx context.Context, id string, forUpdate bool) (*domain.Department, error) {
	sql := `SELECT ` + deptCols + ` FROM departments WHERE id = $1::uuid`
	if forUpdate {
		sql += ` FOR UPDATE`
	}
	return scanDept(r.q.QueryRow(ctx, sql, id))
}

func (r *Repo) SetDepartmentPaused(ctx context.Context, id string, paused bool) error {
	_, err := r.q.Exec(ctx, `UPDATE departments SET is_paused = $2, updated_at = now() WHERE id = $1::uuid`, id, paused)
	return err
}

func (r *Repo) NextSequence(ctx context.Context, deptID string) (int, error) {
	var n int
	err := r.q.QueryRow(ctx,
		`UPDATE departments SET last_token_seq = last_token_seq + 1 WHERE id = $1::uuid RETURNING last_token_seq`,
		deptID).Scan(&n)
	return n, mapErr(err)
}

func (r *Repo) DepartmentStats(ctx context.Context, deptID string) (domain.DeptStats, error) {
	var st domain.DeptStats
	err := r.q.QueryRow(ctx, `
		SELECT
		  COUNT(*) FILTER (WHERE status = 'WAITING'),
		  COUNT(*) FILTER (WHERE status = 'SERVING'),
		  COUNT(*) FILTER (WHERE status = 'COMPLETED'),
		  COUNT(*) FILTER (WHERE status = 'CANCELLED'),
		  COALESCE(SUM(no_show_count), 0),
		  COUNT(*) FILTER (WHERE called_at IS NOT NULL),
		  COALESCE(SUM(EXTRACT(EPOCH FROM (called_at - queue_entered_at))) FILTER (WHERE called_at IS NOT NULL), 0)::float8,
		  COUNT(*) FILTER (WHERE status = 'COMPLETED' AND called_at IS NOT NULL AND completed_at IS NOT NULL),
		  COALESCE(SUM(EXTRACT(EPOCH FROM (completed_at - called_at)))
		           FILTER (WHERE status = 'COMPLETED' AND called_at IS NOT NULL AND completed_at IS NOT NULL), 0)::float8
		FROM tokens WHERE department_id = $1::uuid`, deptID).Scan(
		&st.Waiting, &st.Serving, &st.Completed, &st.Cancelled, &st.NoShows,
		&st.CalledCount, &st.TotalWaitSeconds, &st.TimedCompleted, &st.ServiceSeconds)
	return st, mapErr(err)
}

// --------------------------------------------------------------------- tokens

const tokenCols = `id::text, token_number, department_id::text, priority, status, no_show_count, sequence_no,
	queue_entered_at, created_at, called_at, completed_at, cancelled_at, transferred_from_token_id::text`

// queueOrder is THE ordering rule of the whole system:
// priority first, then the time the token (re-)entered the queue, then its number.
const queueOrder = ` ORDER BY priority DESC, queue_entered_at ASC, sequence_no ASC`

func scanToken(s scanner) (*domain.Token, error) {
	var t domain.Token
	err := s.Scan(&t.ID, &t.TokenNumber, &t.DepartmentID, &t.Priority, &t.Status, &t.NoShowCount, &t.SequenceNo,
		&t.QueueEnteredAt, &t.CreatedAt, &t.CalledAt, &t.CompletedAt, &t.CancelledAt, &t.TransferredFromTokenID)
	if err != nil {
		return nil, mapErr(err)
	}
	return &t, nil
}

func (r *Repo) CreateToken(ctx context.Context, t *domain.Token) error {
	err := r.q.QueryRow(ctx, `
		INSERT INTO tokens (token_number, department_id, priority, status, no_show_count, sequence_no,
		                    queue_entered_at, created_at, transferred_from_token_id)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9::uuid)
		RETURNING id::text`,
		t.TokenNumber, t.DepartmentID, t.Priority, t.Status, t.NoShowCount, t.SequenceNo,
		t.QueueEnteredAt, t.CreatedAt, t.TransferredFromTokenID).Scan(&t.ID)
	return mapErr(err)
}

func (r *Repo) GetToken(ctx context.Context, id string) (*domain.Token, error) {
	return scanToken(r.q.QueryRow(ctx, `SELECT `+tokenCols+` FROM tokens WHERE id = $1::uuid`, id))
}

func (r *Repo) UpdateToken(ctx context.Context, t *domain.Token) error {
	tag, err := r.q.Exec(ctx, `
		UPDATE tokens SET status = $2, no_show_count = $3, queue_entered_at = $4,
		                  called_at = $5, completed_at = $6, cancelled_at = $7
		WHERE id = $1::uuid`,
		t.ID, t.Status, t.NoShowCount, t.QueueEnteredAt, t.CalledAt, t.CompletedAt, t.CancelledAt)
	if err != nil {
		return mapErr(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

func (r *Repo) GetServingToken(ctx context.Context, deptID string) (*domain.Token, error) {
	return scanToken(r.q.QueryRow(ctx,
		`SELECT `+tokenCols+` FROM tokens WHERE department_id = $1::uuid AND status = 'SERVING' LIMIT 1`, deptID))
}

func (r *Repo) NextEligibleToken(ctx context.Context, deptID string) (*domain.Token, error) {
	return scanToken(r.q.QueryRow(ctx,
		`SELECT `+tokenCols+` FROM tokens WHERE department_id = $1::uuid AND status = 'WAITING'`+queueOrder+` LIMIT 1`, deptID))
}

func (r *Repo) ListWaiting(ctx context.Context, deptID string) ([]domain.Token, error) {
	rows, err := r.q.Query(ctx,
		`SELECT `+tokenCols+` FROM tokens WHERE department_id = $1::uuid AND status = 'WAITING'`+queueOrder, deptID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Token{}
	for rows.Next() {
		t, err := scanToken(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *t)
	}
	return out, rows.Err()
}

// QueuePosition = 1 + number of waiting tokens that sort before this one.
func (r *Repo) QueuePosition(ctx context.Context, t *domain.Token) (int, error) {
	var n int
	err := r.q.QueryRow(ctx, `
		SELECT COUNT(*) + 1 FROM tokens
		WHERE department_id = $1::uuid AND status = 'WAITING' AND (
		      priority > $2
		   OR (priority = $2 AND queue_entered_at < $3)
		   OR (priority = $2 AND queue_entered_at = $3 AND sequence_no < $4))`,
		t.DepartmentID, t.Priority, t.QueueEnteredAt, t.SequenceNo).Scan(&n)
	return n, mapErr(err)
}

func (r *Repo) GetTransferTarget(ctx context.Context, tokenID string) (*domain.Token, error) {
	return scanToken(r.q.QueryRow(ctx,
		`SELECT `+tokenCols+` FROM tokens WHERE transferred_from_token_id = $1::uuid LIMIT 1`, tokenID))
}

// --------------------------------------------------------------------- events

func (r *Repo) AddEvent(ctx context.Context, tokenID, eventType string, meta map[string]any) error {
	if meta == nil {
		meta = map[string]any{}
	}
	b, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	_, err = r.q.Exec(ctx,
		`INSERT INTO queue_events (token_id, event_type, metadata) VALUES ($1::uuid, $2, $3::jsonb)`,
		tokenID, eventType, string(b))
	return err
}

func (r *Repo) ListEvents(ctx context.Context, tokenID string) ([]domain.QueueEvent, error) {
	rows, err := r.q.Query(ctx, `
		SELECT id, token_id::text, event_type, metadata::text, created_at
		FROM queue_events WHERE token_id = $1::uuid ORDER BY created_at, id`, tokenID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.QueueEvent{}
	for rows.Next() {
		var e domain.QueueEvent
		var meta string
		if err := rows.Scan(&e.ID, &e.TokenID, &e.EventType, &meta, &e.CreatedAt); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(meta), &e.Metadata); err != nil {
			e.Metadata = map[string]any{}
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------------- users

func (r *Repo) GetUserByEmail(ctx context.Context, email string) (*domain.User, error) {
	var u domain.User
	err := r.q.QueryRow(ctx, `
		SELECT id::text, name, email, password_hash, role, department_id::text, created_at
		FROM users WHERE lower(email) = lower($1)`, email).
		Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.DepartmentID, &u.CreatedAt)
	if err != nil {
		return nil, mapErr(err)
	}
	return &u, nil
}

func (r *Repo) CreateUser(ctx context.Context, u *domain.User) error {
	err := r.q.QueryRow(ctx, `
		INSERT INTO users (name, email, password_hash, role, department_id)
		VALUES ($1, lower($2), $3, $4, $5::uuid) RETURNING id::text, created_at`,
		u.Name, u.Email, u.PasswordHash, u.Role, u.DepartmentID).Scan(&u.ID, &u.CreatedAt)
	return mapErr(err)
}
