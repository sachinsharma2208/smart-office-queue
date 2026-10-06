// Package store defines the persistence contract used by the services.
// The PostgreSQL implementation lives in store/postgres; tests use an
// in-memory fake.
package store

import (
	"context"

	"smartoffice/internal/domain"
)

// Repo is both the "connection" and the "transaction" interface: WithTx runs
// fn with a Repo bound to a single database transaction. If fn returns an
// error the transaction is rolled back, otherwise it is committed.
type Repo interface {
	WithTx(ctx context.Context, fn func(Repo) error) error

	// Departments
	ListDepartments(ctx context.Context) ([]domain.Department, error)
	// GetDepartment with forUpdate=true takes a row lock (SELECT ... FOR UPDATE).
	// Every queue-changing operation locks its department first, which
	// serialises changes per department and prevents race conditions.
	GetDepartment(ctx context.Context, id string, forUpdate bool) (*domain.Department, error)
	SetDepartmentPaused(ctx context.Context, id string, paused bool) error
	// NextSequence atomically increments and returns the department's token counter.
	NextSequence(ctx context.Context, deptID string) (int, error)
	DepartmentStats(ctx context.Context, deptID string) (domain.DeptStats, error)

	// Tokens
	CreateToken(ctx context.Context, t *domain.Token) error
	GetToken(ctx context.Context, id string) (*domain.Token, error)
	UpdateToken(ctx context.Context, t *domain.Token) error
	GetServingToken(ctx context.Context, deptID string) (*domain.Token, error)
	// NextEligibleToken returns the head of the waiting queue:
	// ORDER BY priority DESC, queue_entered_at ASC, sequence_no ASC.
	NextEligibleToken(ctx context.Context, deptID string) (*domain.Token, error)
	ListWaiting(ctx context.Context, deptID string) ([]domain.Token, error)
	// QueuePosition returns the 1-based position of a WAITING token.
	QueuePosition(ctx context.Context, t *domain.Token) (int, error)
	// GetTransferTarget returns the token created when t was transferred.
	GetTransferTarget(ctx context.Context, tokenID string) (*domain.Token, error)

	// Events
	AddEvent(ctx context.Context, tokenID, eventType string, meta map[string]any) error
	ListEvents(ctx context.Context, tokenID string) ([]domain.QueueEvent, error)

	// Users
	GetUserByEmail(ctx context.Context, email string) (*domain.User, error)
	CreateUser(ctx context.Context, u *domain.User) error
}
