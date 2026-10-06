// Package domain holds the core types and business errors. It has no
// dependencies on HTTP, SQL or any framework.
package domain

import (
	"errors"
	"regexp"
	"time"
)

// Token statuses.
const (
	StatusWaiting     = "WAITING"
	StatusServing     = "SERVING"
	StatusCompleted   = "COMPLETED"
	StatusCancelled   = "CANCELLED"
	StatusTransferred = "TRANSFERRED"
)

// Priority levels. A higher number is served first.
const (
	PriorityNormal = 0
	PriorityHigh   = 1
)

// Roles.
const (
	RoleStaff = "STAFF"
	RoleAdmin = "ADMIN"
)

// MaxNoShows is the number of no-shows after which a token is cancelled.
const MaxNoShows = 2

// Business errors. The HTTP layer maps each of these to a status code.
var (
	ErrValidation        = errors.New("invalid input")
	ErrInvalidTransfer   = errors.New("invalid transfer")
	ErrUnauthorized      = errors.New("authentication required or invalid credentials")
	ErrForbidden         = errors.New("you do not have permission to perform this action")
	ErrNotFound          = errors.New("resource not found")
	ErrQueueEmpty        = errors.New("the queue is empty: no waiting token to call")
	ErrDepartmentPaused  = errors.New("this department is temporarily unavailable (paused)")
	ErrServingInProgress = errors.New("a token is already being served in this department; complete it or mark it no-show first")
	ErrTokenServing      = errors.New("this token is currently being served")
	ErrTokenCompleted    = errors.New("this token has already been completed")
	ErrTokenCancelled    = errors.New("this token has already been cancelled")
	ErrInvalidState      = errors.New("this action is not allowed for the token's current status")
	ErrNotNextInQueue    = errors.New("this token is not next in the queue (priority and FIFO order must be respected)")
)

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// IsUUID reports whether s looks like a UUID.
func IsUUID(s string) bool { return uuidRe.MatchString(s) }

// PriorityLabel converts the numeric priority to its API label.
func PriorityLabel(p int) string {
	if p >= PriorityHigh {
		return "PRIORITY"
	}
	return "NORMAL"
}

type Department struct {
	ID                    string
	Name                  string
	Code                  string
	IsPaused              bool
	DefaultServiceMinutes int
	CreatedAt             time.Time
	UpdatedAt             time.Time
}

type Token struct {
	ID                     string
	TokenNumber            string
	DepartmentID           string
	Priority               int
	Status                 string
	NoShowCount            int
	SequenceNo             int
	QueueEnteredAt         time.Time
	CreatedAt              time.Time
	CalledAt               *time.Time
	CompletedAt            *time.Time
	CancelledAt            *time.Time
	TransferredFromTokenID *string
}

type QueueEvent struct {
	ID        int64          `json:"id"`
	TokenID   string         `json:"token_id"`
	EventType string         `json:"event_type"`
	Metadata  map[string]any `json:"metadata"`
	CreatedAt time.Time      `json:"created_at"`
}

type User struct {
	ID           string
	Name         string
	Email        string
	PasswordHash string
	Role         string
	DepartmentID *string
	CreatedAt    time.Time
}

// DeptStats are raw aggregates for one department; the service turns them
// into averages.
type DeptStats struct {
	Waiting          int
	Serving          int
	Completed        int
	Cancelled        int
	NoShows          int     // sum of no_show_count over all tokens
	CalledCount      int     // tokens that have been called at least once
	TotalWaitSeconds float64 // sum(called_at - queue_entered_at) for called tokens
	TimedCompleted   int     // completed tokens with both called_at and completed_at
	ServiceSeconds   float64 // sum(completed_at - called_at) for those tokens
}
