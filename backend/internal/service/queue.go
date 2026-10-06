// Package service contains the queue business rules. The backend is the
// single source of truth: the Flutter app only displays what this package
// computes.
package service

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"smartoffice/internal/domain"
	"smartoffice/internal/store"
)

// Actor is the authenticated staff/admin performing an action.
type Actor struct {
	UserID       string
	Role         string
	DepartmentID *string
}

// CanManage: admins manage every department, staff only their own.
func (a Actor) CanManage(deptID string) bool {
	if a.Role == domain.RoleAdmin {
		return true
	}
	return a.Role == domain.RoleStaff && a.DepartmentID != nil && *a.DepartmentID == deptID
}

// Queue implements all queue operations.
type Queue struct {
	repo store.Repo
	now  func() time.Time
}

func NewQueue(repo store.Repo) *Queue {
	// Truncate to microseconds: PostgreSQL's precision. Keeps in-memory
	// timestamps identical to the stored ones so ordering comparisons are exact.
	return NewQueueWithClock(repo, func() time.Time { return time.Now().UTC().Truncate(time.Microsecond) })
}

// NewQueueWithClock allows tests to inject a deterministic clock.
func NewQueueWithClock(repo store.Repo, clock func() time.Time) *Queue {
	return &Queue{repo: repo, now: clock}
}

func requireUUID(label, id string) error {
	if !domain.IsUUID(id) {
		return fmt.Errorf("%w: %s is not a valid id", domain.ErrValidation, label)
	}
	return nil
}

func parsePriority(p string) (int, error) {
	switch strings.ToUpper(strings.TrimSpace(p)) {
	case "", "NORMAL":
		return domain.PriorityNormal, nil
	case "PRIORITY":
		return domain.PriorityHigh, nil
	}
	return 0, fmt.Errorf("%w: priority must be NORMAL or PRIORITY", domain.ErrValidation)
}

// notServingError explains why a token cannot be completed / marked no-show.
func notServingError(status string) error {
	switch status {
	case domain.StatusCompleted:
		return domain.ErrTokenCompleted
	case domain.StatusCancelled:
		return domain.ErrTokenCancelled
	default:
		return fmt.Errorf("%w: token is %s, not SERVING", domain.ErrInvalidState, status)
	}
}

// statusError explains why a non-WAITING token cannot be cancelled/called/transferred.
func statusError(status string) error {
	switch status {
	case domain.StatusServing:
		return domain.ErrTokenServing
	case domain.StatusCompleted:
		return domain.ErrTokenCompleted
	case domain.StatusCancelled:
		return domain.ErrTokenCancelled
	default:
		return fmt.Errorf("%w: token is %s", domain.ErrInvalidState, status)
	}
}

// ---------------------------------------------------------------- departments

func (s *Queue) departmentView(ctx context.Context, d *domain.Department) (*DepartmentView, error) {
	st, err := s.repo.DepartmentStats(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	avg := avgServiceMinutes(d, st)
	v := &DepartmentView{
		ID: d.ID, Name: d.Name, Code: d.Code, IsPaused: d.IsPaused,
		WaitingCount: st.Waiting, AvgServiceMinutes: avg,
		EstimatedWaitMinutes: estimateMinutes(st.Waiting, avg),
	}
	serving, err := s.repo.GetServingToken(ctx, d.ID)
	if err == nil {
		v.ServingToken = &serving.TokenNumber
	} else if !errors.Is(err, domain.ErrNotFound) {
		return nil, err
	}
	return v, nil
}

func (s *Queue) ListDepartments(ctx context.Context) ([]DepartmentView, error) {
	ds, err := s.repo.ListDepartments(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]DepartmentView, 0, len(ds))
	for i := range ds {
		v, err := s.departmentView(ctx, &ds[i])
		if err != nil {
			return nil, err
		}
		out = append(out, *v)
	}
	return out, nil
}

func (s *Queue) GetDepartment(ctx context.Context, id string) (*DepartmentView, error) {
	if err := requireUUID("department id", id); err != nil {
		return nil, err
	}
	d, err := s.repo.GetDepartment(ctx, id, false)
	if err != nil {
		return nil, err
	}
	return s.departmentView(ctx, d)
}

// SetPaused pauses/resumes a department. Pausing only blocks NEW tokens and
// incoming transfers; tokens already in the queue stay exactly where they are.
func (s *Queue) SetPaused(ctx context.Context, deptID string, paused bool) (*DepartmentView, error) {
	if err := requireUUID("department id", deptID); err != nil {
		return nil, err
	}
	err := s.repo.WithTx(ctx, func(r store.Repo) error {
		if _, err := r.GetDepartment(ctx, deptID, true); err != nil {
			return err
		}
		return r.SetDepartmentPaused(ctx, deptID, paused)
	})
	if err != nil {
		return nil, err
	}
	return s.GetDepartment(ctx, deptID)
}

// --------------------------------------------------------------------- tokens

// enqueue creates a WAITING token with the department's next number. Must be
// called inside a transaction that holds the department lock.
func (s *Queue) enqueue(ctx context.Context, r store.Repo, d *domain.Department, prio int, from *string) (*domain.Token, error) {
	seq, err := r.NextSequence(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	now := s.now()
	t := &domain.Token{
		TokenNumber: fmt.Sprintf("%s-%03d", d.Code, seq), DepartmentID: d.ID,
		Priority: prio, Status: domain.StatusWaiting, SequenceNo: seq,
		QueueEnteredAt: now, CreatedAt: now, TransferredFromTokenID: from,
	}
	if err := r.CreateToken(ctx, t); err != nil {
		return nil, err
	}
	return t, nil
}

// CreateToken issues a new token. Rejected while the department is paused.
func (s *Queue) CreateToken(ctx context.Context, deptID, priority string) (*TokenView, error) {
	if err := requireUUID("department_id", deptID); err != nil {
		return nil, err
	}
	prio, err := parsePriority(priority)
	if err != nil {
		return nil, err
	}
	var tok *domain.Token
	err = s.repo.WithTx(ctx, func(r store.Repo) error {
		d, err := r.GetDepartment(ctx, deptID, true) // lock: serialises numbering + queue changes
		if err != nil {
			return err
		}
		if d.IsPaused {
			return domain.ErrDepartmentPaused
		}
		t, err := s.enqueue(ctx, r, d, prio, nil)
		if err != nil {
			return err
		}
		tok = t
		return r.AddEvent(ctx, t.ID, "CREATED", map[string]any{"priority": domain.PriorityLabel(prio)})
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, tok, false)
}

// GetToken returns a token with live position/ETA and its event history.
func (s *Queue) GetToken(ctx context.Context, id string) (*TokenView, error) {
	if err := requireUUID("token id", id); err != nil {
		return nil, err
	}
	t, err := s.repo.GetToken(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, t, true)
}

func (s *Queue) tokenView(ctx context.Context, t *domain.Token, withEvents bool) (*TokenView, error) {
	d, err := s.repo.GetDepartment(ctx, t.DepartmentID, false)
	if err != nil {
		return nil, err
	}
	st, err := s.repo.DepartmentStats(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	avg := avgServiceMinutes(d, st)
	v := baseView(t, d, avg)

	switch t.Status {
	case domain.StatusWaiting:
		pos, err := s.repo.QueuePosition(ctx, t)
		if err != nil {
			return nil, err
		}
		ahead := pos - 1
		est := estimateMinutes(ahead, avg)
		v.QueuePosition, v.PeopleAhead, v.EstimatedWaitMinutes = &pos, &ahead, &est
	case domain.StatusTransferred:
		child, err := s.repo.GetTransferTarget(ctx, t.ID)
		if err == nil {
			v.TransferredToTokenID, v.TransferredToTokenNumber = &child.ID, &child.TokenNumber
		} else if !errors.Is(err, domain.ErrNotFound) {
			return nil, err
		}
	}
	if withEvents {
		ev, err := s.repo.ListEvents(ctx, t.ID)
		if err != nil {
			return nil, err
		}
		v.Events = ev
	}
	return v, nil
}

// withLockedToken runs fn inside a transaction while holding the lock of the
// token's department. Lock order is always department -> (token), so two
// operations can never deadlock on a single department.
func (s *Queue) withLockedToken(ctx context.Context, id string, actor *Actor,
	fn func(r store.Repo, t *domain.Token, d *domain.Department) error) (*domain.Token, error) {

	if err := requireUUID("token id", id); err != nil {
		return nil, err
	}
	var out *domain.Token
	err := s.repo.WithTx(ctx, func(r store.Repo) error {
		t0, err := r.GetToken(ctx, id)
		if err != nil {
			return err
		}
		if actor != nil && !actor.CanManage(t0.DepartmentID) {
			return domain.ErrForbidden
		}
		d, err := r.GetDepartment(ctx, t0.DepartmentID, true)
		if err != nil {
			return err
		}
		t, err := r.GetToken(ctx, id) // re-read now that we hold the lock
		if err != nil {
			return err
		}
		if err := fn(r, t, d); err != nil {
			return err
		}
		out = t
		return nil
	})
	return out, err
}

// Cancel lets a visitor cancel a WAITING token.
func (s *Queue) Cancel(ctx context.Context, id string) (*TokenView, error) {
	t, err := s.withLockedToken(ctx, id, nil, func(r store.Repo, t *domain.Token, _ *domain.Department) error {
		if t.Status != domain.StatusWaiting {
			return statusError(t.Status)
		}
		now := s.now()
		t.Status, t.CancelledAt = domain.StatusCancelled, &now
		if err := r.UpdateToken(ctx, t); err != nil {
			return err
		}
		return r.AddEvent(ctx, t.ID, "CANCELLED", map[string]any{"by": "visitor"})
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, t, true)
}

// startServing moves a WAITING token to SERVING.
func (s *Queue) startServing(ctx context.Context, r store.Repo, t *domain.Token, actor Actor) error {
	now := s.now()
	t.Status, t.CalledAt = domain.StatusServing, &now
	if err := r.UpdateToken(ctx, t); err != nil {
		return err
	}
	return r.AddEvent(ctx, t.ID, "CALLED", map[string]any{"by": actor.UserID})
}

// ensureNobodyServing returns ErrServingInProgress if the department already
// has a SERVING token.
func ensureNobodyServing(ctx context.Context, r store.Repo, deptID string) error {
	_, err := r.GetServingToken(ctx, deptID)
	switch {
	case err == nil:
		return domain.ErrServingInProgress
	case errors.Is(err, domain.ErrNotFound):
		return nil
	default:
		return err
	}
}

// CallNext calls the head of the queue (priority first, then FIFO).
func (s *Queue) CallNext(ctx context.Context, deptID string, actor Actor) (*TokenView, error) {
	if err := requireUUID("department id", deptID); err != nil {
		return nil, err
	}
	if !actor.CanManage(deptID) {
		return nil, domain.ErrForbidden
	}
	var called *domain.Token
	err := s.repo.WithTx(ctx, func(r store.Repo) error {
		if _, err := r.GetDepartment(ctx, deptID, true); err != nil {
			return err
		}
		if err := ensureNobodyServing(ctx, r, deptID); err != nil { // never interrupt a serving token
			return err
		}
		next, err := r.NextEligibleToken(ctx, deptID)
		if errors.Is(err, domain.ErrNotFound) {
			return domain.ErrQueueEmpty
		}
		if err != nil {
			return err
		}
		if err := s.startServing(ctx, r, next, actor); err != nil {
			return err
		}
		called = next
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, called, true)
}

// CallToken calls one specific token, but only if it is the head of the queue.
func (s *Queue) CallToken(ctx context.Context, id string, actor Actor) (*TokenView, error) {
	t, err := s.withLockedToken(ctx, id, &actor, func(r store.Repo, t *domain.Token, d *domain.Department) error {
		if t.Status != domain.StatusWaiting {
			return statusError(t.Status)
		}
		if err := ensureNobodyServing(ctx, r, d.ID); err != nil {
			return err
		}
		head, err := r.NextEligibleToken(ctx, d.ID)
		if err != nil {
			return err
		}
		if head.ID != t.ID {
			return domain.ErrNotNextInQueue
		}
		return s.startServing(ctx, r, t, actor)
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, t, true)
}

// Complete finishes the SERVING token.
func (s *Queue) Complete(ctx context.Context, id string, actor Actor) (*TokenView, error) {
	t, err := s.withLockedToken(ctx, id, &actor, func(r store.Repo, t *domain.Token, _ *domain.Department) error {
		if t.Status != domain.StatusServing {
			return notServingError(t.Status)
		}
		now := s.now()
		t.Status, t.CompletedAt = domain.StatusCompleted, &now
		if err := r.UpdateToken(ctx, t); err != nil {
			return err
		}
		return r.AddEvent(ctx, t.ID, "COMPLETED", map[string]any{"by": actor.UserID})
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, t, true)
}

// NoShow handles a called token whose visitor did not show up.
//
//	1st no-show: no_show_count=1, token goes back to WAITING at the very END of
//	             the queue: priority is dropped and queue_entered_at = now.
//	2nd no-show: no_show_count=2, token is CANCELLED (never eligible again).
func (s *Queue) NoShow(ctx context.Context, id string, actor Actor) (*TokenView, error) {
	t, err := s.withLockedToken(ctx, id, &actor, func(r store.Repo, t *domain.Token, _ *domain.Department) error {
		if t.Status != domain.StatusServing {
			return notServingError(t.Status)
		}
		now := s.now()
		t.NoShowCount++
		event := "NO_SHOW_REQUEUED"
		priorityRemoved := false
		if t.NoShowCount >= domain.MaxNoShows {
			t.Status, t.CancelledAt = domain.StatusCancelled, &now
			event = "NO_SHOW_CANCELLED"
		} else {
			// Back to WAITING at the very END of the queue: the token loses its
			// priority (otherwise it would still sort ahead of normal tokens)
			// and re-enters the queue now.
			priorityRemoved = t.Priority != domain.PriorityNormal
			t.Priority = domain.PriorityNormal
			t.Status, t.QueueEnteredAt, t.CalledAt = domain.StatusWaiting, now, nil
		}
		if err := r.UpdateToken(ctx, t); err != nil {
			return err
		}
		return r.AddEvent(ctx, t.ID, event, map[string]any{
			"by": actor.UserID, "no_show_count": t.NoShowCount, "priority_removed": priorityRemoved,
		})
	})
	if err != nil {
		return nil, err
	}
	return s.tokenView(ctx, t, true)
}

// Transfer moves a WAITING token to another department. The original token is
// kept (status TRANSFERRED) and a NEW token is issued in the target
// department, linked through transferred_from_token_id.
func (s *Queue) Transfer(ctx context.Context, id, targetDeptID string, actor Actor) (*TransferResult, error) {
	if err := requireUUID("token id", id); err != nil {
		return nil, err
	}
	if err := requireUUID("target_department_id", targetDeptID); err != nil {
		return nil, err
	}
	var oldTok, newTok *domain.Token
	err := s.repo.WithTx(ctx, func(r store.Repo) error {
		t0, err := r.GetToken(ctx, id)
		if err != nil {
			return err
		}
		if !actor.CanManage(t0.DepartmentID) {
			return domain.ErrForbidden
		}
		if t0.DepartmentID == targetDeptID {
			return fmt.Errorf("%w: token is already in that department", domain.ErrInvalidTransfer)
		}
		// Lock both departments in a fixed (sorted) order so two opposite
		// transfers (A->B and B->A) cannot deadlock.
		ids := []string{t0.DepartmentID, targetDeptID}
		sort.Strings(ids)
		depts := map[string]*domain.Department{}
		for _, did := range ids {
			d, err := r.GetDepartment(ctx, did, true)
			if errors.Is(err, domain.ErrNotFound) && did == targetDeptID {
				return fmt.Errorf("%w: target department does not exist", domain.ErrInvalidTransfer)
			}
			if err != nil {
				return err
			}
			depts[did] = d
		}
		t, err := r.GetToken(ctx, id)
		if err != nil {
			return err
		}
		if t.Status != domain.StatusWaiting {
			return statusError(t.Status) // only WAITING tokens can be transferred
		}
		target := depts[targetDeptID]
		if target.IsPaused {
			return fmt.Errorf("%w: cannot transfer into %s", domain.ErrDepartmentPaused, target.Name)
		}
		nt, err := s.enqueue(ctx, r, target, t.Priority, &t.ID) // priority is preserved
		if err != nil {
			return err
		}
		t.Status = domain.StatusTransferred
		if err := r.UpdateToken(ctx, t); err != nil {
			return err
		}
		meta := map[string]any{
			"by": actor.UserID, "from_department": depts[t.DepartmentID].Name, "to_department": target.Name,
			"from_token": t.TokenNumber, "to_token": nt.TokenNumber,
		}
		if err := r.AddEvent(ctx, t.ID, "TRANSFERRED_OUT", meta); err != nil {
			return err
		}
		if err := r.AddEvent(ctx, nt.ID, "TRANSFERRED_IN", meta); err != nil {
			return err
		}
		oldTok, newTok = t, nt
		return nil
	})
	if err != nil {
		return nil, err
	}
	ov, err := s.tokenView(ctx, oldTok, true)
	if err != nil {
		return nil, err
	}
	nv, err := s.tokenView(ctx, newTok, true)
	if err != nil {
		return nil, err
	}
	return &TransferResult{OldToken: ov, NewToken: nv}, nil
}

// ---------------------------------------------------------------------- queue

// Queue returns the live queue of a department. Positions are simply the
// index in the ordered waiting list (priority DESC, entered ASC, sequence ASC).
func (s *Queue) Queue(ctx context.Context, deptID string) (*QueueView, error) {
	if err := requireUUID("department id", deptID); err != nil {
		return nil, err
	}
	d, err := s.repo.GetDepartment(ctx, deptID, false)
	if err != nil {
		return nil, err
	}
	st, err := s.repo.DepartmentStats(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	avg := avgServiceMinutes(d, st)
	dv, err := s.departmentView(ctx, d)
	if err != nil {
		return nil, err
	}
	waiting, err := s.repo.ListWaiting(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	view := &QueueView{Department: *dv, Waiting: make([]TokenView, 0, len(waiting)), Stats: statsView(d, st)}
	for i := range waiting {
		v := baseView(&waiting[i], d, avg)
		pos, ahead := i+1, i
		est := estimateMinutes(ahead, avg)
		v.QueuePosition, v.PeopleAhead, v.EstimatedWaitMinutes = &pos, &ahead, &est
		view.Waiting = append(view.Waiting, *v)
	}
	serving, err := s.repo.GetServingToken(ctx, d.ID)
	if err == nil {
		view.Serving = baseView(serving, d, avg)
	} else if !errors.Is(err, domain.ErrNotFound) {
		return nil, err
	}
	return view, nil
}

// ------------------------------------------------------------------ dashboard

func (s *Queue) Dashboard(ctx context.Context) (*DashboardView, error) {
	ds, err := s.repo.ListDepartments(ctx)
	if err != nil {
		return nil, err
	}
	out := &DashboardView{Departments: make([]DeptStatsView, 0, len(ds)), GeneratedAt: s.now()}
	var totalWait float64
	var totalCalled int
	for i := range ds {
		st, err := s.repo.DepartmentStats(ctx, ds[i].ID)
		if err != nil {
			return nil, err
		}
		out.Departments = append(out.Departments, statsView(&ds[i], st))
		t := &out.Totals
		t.Waiting += st.Waiting
		t.Serving += st.Serving
		t.Completed += st.Completed
		t.Cancelled += st.Cancelled
		t.NoShows += st.NoShows
		if ds[i].IsPaused {
			t.PausedDepartments++
		}
		totalWait += st.TotalWaitSeconds
		totalCalled += st.CalledCount
	}
	out.Totals.TotalDepartments = len(ds)
	if totalCalled > 0 {
		out.Totals.AvgWaitingMinutes = round1(totalWait / float64(totalCalled) / 60)
	}
	return out, nil
}

func (s *Queue) DepartmentDashboard(ctx context.Context, deptID string, actor Actor) (*DeptStatsView, error) {
	if err := requireUUID("department id", deptID); err != nil {
		return nil, err
	}
	if !actor.CanManage(deptID) {
		return nil, domain.ErrForbidden
	}
	d, err := s.repo.GetDepartment(ctx, deptID, false)
	if err != nil {
		return nil, err
	}
	st, err := s.repo.DepartmentStats(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	v := statsView(d, st)
	return &v, nil
}
