package service

import (
	"math"
	"time"

	"smartoffice/internal/domain"
)

// Estimation settings (see README "Estimated waiting time").
const (
	// Until a department has this many timed completions we trust its
	// configured default service time instead of a tiny, noisy average.
	minSamplesForAverage = 5
	// Floor for a measured average so one very fast demo session does not
	// make every estimate "0 minutes".
	minAvgServiceMinutes = 1.0
)

// DepartmentView is what the API returns for a department.
type DepartmentView struct {
	ID                   string  `json:"id"`
	Name                 string  `json:"name"`
	Code                 string  `json:"code"`
	IsPaused             bool    `json:"is_paused"`
	WaitingCount         int     `json:"waiting_count"`
	ServingToken         *string `json:"serving_token"`
	AvgServiceMinutes    float64 `json:"avg_service_minutes"`
	EstimatedWaitMinutes int     `json:"estimated_wait_minutes"` // for a new NORMAL token joining now
}

// TokenView is what the API returns for a token. QueuePosition,
// PeopleAhead and EstimatedWaitMinutes are computed on every request from the
// current queue ordering - they are never stored, so they can't go stale.
type TokenView struct {
	ID                       string              `json:"id"`
	TokenNumber              string              `json:"token_number"`
	DepartmentID             string              `json:"department_id"`
	DepartmentName           string              `json:"department_name"`
	DepartmentCode           string              `json:"department_code"`
	DepartmentPaused         bool                `json:"department_paused"`
	Priority                 string              `json:"priority"`
	Status                   string              `json:"status"`
	NoShowCount              int                 `json:"no_show_count"`
	QueuePosition            *int                `json:"queue_position"`
	PeopleAhead              *int                `json:"people_ahead"`
	EstimatedWaitMinutes     *int                `json:"estimated_wait_minutes"`
	AvgServiceMinutes        float64             `json:"avg_service_minutes"`
	CreatedAt                time.Time           `json:"created_at"`
	CalledAt                 *time.Time          `json:"called_at"`
	CompletedAt              *time.Time          `json:"completed_at"`
	CancelledAt              *time.Time          `json:"cancelled_at"`
	TransferredFromTokenID   *string             `json:"transferred_from_token_id"`
	TransferredToTokenID     *string             `json:"transferred_to_token_id"`
	TransferredToTokenNumber *string             `json:"transferred_to_token_number"`
	Events                   []domain.QueueEvent `json:"events,omitempty"`
}

// QueueView is the live queue of one department.
type QueueView struct {
	Department DepartmentView `json:"department"`
	Serving    *TokenView     `json:"serving"`
	Waiting    []TokenView    `json:"waiting"`
	Stats      DeptStatsView  `json:"stats"`
}

// DeptStatsView holds the dashboard numbers for one department.
type DeptStatsView struct {
	DepartmentID      string  `json:"department_id"`
	DepartmentName    string  `json:"department_name"`
	DepartmentCode    string  `json:"department_code"`
	IsPaused          bool    `json:"is_paused"`
	Waiting           int     `json:"waiting"`
	Serving           int     `json:"serving"`
	Completed         int     `json:"completed"`
	Cancelled         int     `json:"cancelled"`
	NoShows           int     `json:"no_shows"`
	AvgWaitingMinutes float64 `json:"avg_waiting_minutes"`
	AvgServiceMinutes float64 `json:"avg_service_minutes"`
}

type DashboardTotals struct {
	Waiting           int     `json:"waiting"`
	Serving           int     `json:"serving"`
	Completed         int     `json:"completed"`
	Cancelled         int     `json:"cancelled"`
	NoShows           int     `json:"no_shows"`
	AvgWaitingMinutes float64 `json:"avg_waiting_minutes"`
	PausedDepartments int     `json:"paused_departments"`
	TotalDepartments  int     `json:"total_departments"`
}

type DashboardView struct {
	Totals      DashboardTotals `json:"totals"`
	Departments []DeptStatsView `json:"departments"`
	GeneratedAt time.Time       `json:"generated_at"`
}

// TransferResult is returned by a successful transfer.
type TransferResult struct {
	OldToken *TokenView `json:"old_token"`
	NewToken *TokenView `json:"new_token"`
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

// avgServiceMinutes: measured average service time (completed_at - called_at),
// or the department default while there is not enough data.
func avgServiceMinutes(d *domain.Department, st domain.DeptStats) float64 {
	if st.TimedCompleted >= minSamplesForAverage {
		avg := st.ServiceSeconds / float64(st.TimedCompleted) / 60
		if avg < minAvgServiceMinutes {
			avg = minAvgServiceMinutes
		}
		return round1(avg)
	}
	return float64(d.DefaultServiceMinutes)
}

// estimateMinutes: people ahead x average service time.
func estimateMinutes(ahead int, avg float64) int {
	return int(math.Round(float64(ahead) * avg))
}

func baseView(t *domain.Token, d *domain.Department, avg float64) *TokenView {
	return &TokenView{
		ID: t.ID, TokenNumber: t.TokenNumber,
		DepartmentID: d.ID, DepartmentName: d.Name, DepartmentCode: d.Code, DepartmentPaused: d.IsPaused,
		Priority: domain.PriorityLabel(t.Priority), Status: t.Status, NoShowCount: t.NoShowCount,
		AvgServiceMinutes: avg,
		CreatedAt:         t.CreatedAt, CalledAt: t.CalledAt, CompletedAt: t.CompletedAt, CancelledAt: t.CancelledAt,
		TransferredFromTokenID: t.TransferredFromTokenID,
	}
}

func statsView(d *domain.Department, st domain.DeptStats) DeptStatsView {
	avgWait := 0.0
	if st.CalledCount > 0 {
		avgWait = round1(st.TotalWaitSeconds / float64(st.CalledCount) / 60)
	}
	return DeptStatsView{
		DepartmentID: d.ID, DepartmentName: d.Name, DepartmentCode: d.Code, IsPaused: d.IsPaused,
		Waiting: st.Waiting, Serving: st.Serving, Completed: st.Completed, Cancelled: st.Cancelled,
		NoShows: st.NoShows, AvgWaitingMinutes: avgWait, AvgServiceMinutes: avgServiceMinutes(d, st),
	}
}
