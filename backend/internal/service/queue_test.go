package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"smartoffice/internal/domain"
)

type env struct {
	t     *testing.T
	q     *Queue
	repo  *fakeRepo
	ctx   context.Context
	admin Actor
}

// newEnv builds a Queue over the fake repo with a clock that advances one
// second per call, so FIFO order is deterministic.
func newEnv(t *testing.T) *env {
	repo := newFakeRepo()
	now := time.Date(2026, 1, 1, 9, 0, 0, 0, time.UTC)
	clock := func() time.Time { now = now.Add(time.Second); return now }
	return &env{t: t, q: NewQueueWithClock(repo, clock), repo: repo, ctx: context.Background(),
		admin: Actor{UserID: "admin", Role: domain.RoleAdmin}}
}

func (e *env) dept(code string) string {
	for _, d := range e.repo.depts {
		if d.Code == code {
			return d.ID
		}
	}
	e.t.Fatalf("unknown department %s", code)
	return ""
}

func (e *env) newToken(code, priority string) *TokenView {
	e.t.Helper()
	v, err := e.q.CreateToken(e.ctx, e.dept(code), priority)
	if err != nil {
		e.t.Fatalf("CreateToken(%s,%s): %v", code, priority, err)
	}
	return v
}

func (e *env) callNext(code string) *TokenView {
	e.t.Helper()
	v, err := e.q.CallNext(e.ctx, e.dept(code), e.admin)
	if err != nil {
		e.t.Fatalf("CallNext(%s): %v", code, err)
	}
	return v
}

func (e *env) complete(id string) {
	e.t.Helper()
	if _, err := e.q.Complete(e.ctx, id, e.admin); err != nil {
		e.t.Fatalf("Complete: %v", err)
	}
}

func (e *env) get(id string) *TokenView {
	e.t.Helper()
	v, err := e.q.GetToken(e.ctx, id)
	if err != nil {
		e.t.Fatalf("GetToken: %v", err)
	}
	return v
}

func wantNumber(t *testing.T, got *TokenView, want string) {
	t.Helper()
	if got.TokenNumber != want {
		t.Fatalf("token = %s, want %s", got.TokenNumber, want)
	}
}

func wantErr(t *testing.T, err, want error) {
	t.Helper()
	if !errors.Is(err, want) {
		t.Fatalf("error = %v, want %v", err, want)
	}
}

func TestTokenNumbersArePerDepartment(t *testing.T) {
	e := newEnv(t)
	wantNumber(t, e.newToken("IT", ""), "IT-001")
	wantNumber(t, e.newToken("IT", ""), "IT-002")
	wantNumber(t, e.newToken("HR", ""), "HR-001")
	wantNumber(t, e.newToken("ACC", ""), "ACC-001")
	wantNumber(t, e.newToken("ADM", ""), "ADM-001")
	wantNumber(t, e.newToken("HR", ""), "HR-002")
}

// 1. Normal FIFO queue
func TestFIFOQueue(t *testing.T) {
	e := newEnv(t)
	for i := 0; i < 3; i++ {
		e.newToken("IT", "")
	}
	for _, want := range []string{"IT-001", "IT-002", "IT-003"} {
		got := e.callNext("IT")
		wantNumber(t, got, want)
		e.complete(got.ID)
	}
	_, err := e.q.CallNext(e.ctx, e.dept("IT"), e.admin)
	wantErr(t, err, domain.ErrQueueEmpty)
}

// 2. Priority tokens are ordered ahead of normal ones, FIFO within a level.
func TestPriorityOrdering(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")               // IT-001 normal
	e.newToken("IT", "")               // IT-002 normal
	p3 := e.newToken("IT", "PRIORITY") // IT-003 priority
	e.newToken("IT", "")               // IT-004 normal
	e.newToken("IT", "PRIORITY")       // IT-005 priority

	if p3.QueuePosition == nil || *p3.QueuePosition != 1 {
		t.Fatalf("first priority token should be position 1, got %v", p3.QueuePosition)
	}
	for _, want := range []string{"IT-003", "IT-005", "IT-001", "IT-002", "IT-004"} {
		got := e.callNext("IT")
		wantNumber(t, got, want)
		e.complete(got.ID)
	}
}

// 3. A priority token must never interrupt the token being served.
func TestPriorityDoesNotInterruptServing(t *testing.T) {
	e := newEnv(t)
	first := e.newToken("IT", "")
	e.newToken("IT", "")
	e.newToken("IT", "")
	serving := e.callNext("IT")
	wantNumber(t, serving, "IT-001")

	prio := e.newToken("IT", "PRIORITY") // IT-004 arrives while IT-001 is served

	if got := e.get(first.ID); got.Status != domain.StatusServing {
		t.Fatalf("IT-001 status = %s, want SERVING", got.Status)
	}
	_, err := e.q.CallNext(e.ctx, e.dept("IT"), e.admin)
	wantErr(t, err, domain.ErrServingInProgress)

	e.complete(first.ID)
	got := e.callNext("IT")
	wantNumber(t, got, prio.TokenNumber) // IT-004 jumps ahead of IT-002 / IT-003
	e.complete(got.ID)
	wantNumber(t, e.callNext("IT"), "IT-002")
}

// 4. First no-show: count=1, token goes to the END of the waiting queue.
func TestFirstNoShowMovesTokenToEnd(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")
	e.newToken("IT", "")
	e.newToken("IT", "")
	serving := e.callNext("IT") // IT-001

	v, err := e.q.NoShow(e.ctx, serving.ID, e.admin)
	if err != nil {
		t.Fatal(err)
	}
	if v.Status != domain.StatusWaiting || v.NoShowCount != 1 {
		t.Fatalf("after first no-show: status=%s count=%d", v.Status, v.NoShowCount)
	}
	if v.QueuePosition == nil || *v.QueuePosition != 3 {
		t.Fatalf("token should be last (position 3), got %v", v.QueuePosition)
	}
	wantNumber(t, e.callNext("IT"), "IT-002") // IT-001 no longer first
}

// 4b. A PRIORITY token's first no-show also sends it to the very end
// (it loses its priority, so it does not stay ahead of normal tokens).
func TestPriorityTokenFirstNoShowGoesToVeryEnd(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")              // IT-001 normal
	e.newToken("IT", "")              // IT-002 normal
	p := e.newToken("IT", "PRIORITY") // IT-003 priority
	serving := e.callNext("IT")
	wantNumber(t, serving, p.TokenNumber)

	v, err := e.q.NoShow(e.ctx, serving.ID, e.admin)
	if err != nil {
		t.Fatal(err)
	}
	if v.Status != domain.StatusWaiting || v.Priority != "NORMAL" || v.NoShowCount != 1 {
		t.Fatalf("after no-show: status=%s priority=%s count=%d", v.Status, v.Priority, v.NoShowCount)
	}
	if v.QueuePosition == nil || *v.QueuePosition != 3 {
		t.Fatalf("token should be the very last (position 3), got %v", v.QueuePosition)
	}
	wantNumber(t, e.callNext("IT"), "IT-001")
}

// 5. Second no-show: count=2, token is cancelled and never called again.
func TestSecondNoShowCancelsToken(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")
	first := e.callNext("IT")
	if _, err := e.q.NoShow(e.ctx, first.ID, e.admin); err != nil {
		t.Fatal(err)
	}
	again := e.callNext("IT") // only token in queue -> called again
	wantNumber(t, again, "IT-001")
	v, err := e.q.NoShow(e.ctx, again.ID, e.admin)
	if err != nil {
		t.Fatal(err)
	}
	if v.Status != domain.StatusCancelled || v.NoShowCount != 2 || v.CancelledAt == nil {
		t.Fatalf("after second no-show: status=%s count=%d cancelled_at=%v", v.Status, v.NoShowCount, v.CancelledAt)
	}
	_, err = e.q.CallNext(e.ctx, e.dept("IT"), e.admin)
	wantErr(t, err, domain.ErrQueueEmpty) // no longer eligible
}

// 6. Paused department rejects new tokens but keeps existing ones.
func TestPausedDepartmentRejectsNewTokens(t *testing.T) {
	e := newEnv(t)
	existing := e.newToken("IT", "")
	if _, err := e.q.SetPaused(e.ctx, e.dept("IT"), true); err != nil {
		t.Fatal(err)
	}
	_, err := e.q.CreateToken(e.ctx, e.dept("IT"), "")
	wantErr(t, err, domain.ErrDepartmentPaused)

	if got := e.get(existing.ID); got.Status != domain.StatusWaiting || got.QueuePosition == nil || *got.QueuePosition != 1 {
		t.Fatalf("existing token must stay in queue, got %+v", got)
	}
	// other departments are unaffected
	e.newToken("HR", "")

	if _, err := e.q.SetPaused(e.ctx, e.dept("IT"), false); err != nil {
		t.Fatal(err)
	}
	wantNumber(t, e.newToken("IT", ""), "IT-002")
}

// 7. Token cancellation rules.
func TestCancelToken(t *testing.T) {
	e := newEnv(t)
	a := e.newToken("IT", "")
	b := e.newToken("IT", "")
	c := e.newToken("IT", "")

	v, err := e.q.Cancel(e.ctx, b.ID)
	if err != nil || v.Status != domain.StatusCancelled || v.CancelledAt == nil {
		t.Fatalf("cancel waiting token: %v %+v", err, v)
	}
	if got := e.get(c.ID); *got.QueuePosition != 2 { // position updates automatically
		t.Fatalf("IT-003 position = %d, want 2", *got.QueuePosition)
	}
	_, err = e.q.Cancel(e.ctx, b.ID)
	wantErr(t, err, domain.ErrTokenCancelled)

	serving := e.callNext("IT")
	wantNumber(t, serving, a.TokenNumber)
	_, err = e.q.Cancel(e.ctx, a.ID)
	wantErr(t, err, domain.ErrTokenServing)

	e.complete(a.ID)
	_, err = e.q.Cancel(e.ctx, a.ID)
	wantErr(t, err, domain.ErrTokenCompleted)

	_, err = e.q.Cancel(e.ctx, "not-a-uuid")
	wantErr(t, err, domain.ErrValidation)
	_, err = e.q.Cancel(e.ctx, fakeID(99999))
	wantErr(t, err, domain.ErrNotFound)
}

// 8. Transfer.
func TestTransferToken(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")
	second := e.newToken("IT", "PRIORITY")
	third := e.newToken("IT", "")
	e.newToken("HR", "") // HR-001 already waiting

	res, err := e.q.Transfer(e.ctx, second.ID, e.dept("HR"), e.admin)
	if err != nil {
		t.Fatal(err)
	}
	wantNumber(t, res.NewToken, "HR-002")
	if res.OldToken.Status != domain.StatusTransferred || res.OldToken.TransferredToTokenNumber == nil || *res.OldToken.TransferredToTokenNumber != "HR-002" {
		t.Fatalf("old token not linked to new one: %+v", res.OldToken)
	}
	if res.NewToken.TransferredFromTokenID == nil || *res.NewToken.TransferredFromTokenID != second.ID {
		t.Fatal("new token must reference the original token")
	}
	if res.NewToken.Priority != "PRIORITY" || *res.NewToken.QueuePosition != 1 {
		t.Fatalf("priority must be preserved: %+v", res.NewToken)
	}
	itq, _ := e.q.Queue(e.ctx, e.dept("IT"))
	if len(itq.Waiting) != 2 || *e.get(third.ID).QueuePosition != 2 {
		t.Fatalf("IT queue should have 2 waiting and positions recalculated, got %d", len(itq.Waiting))
	}
	hrq, _ := e.q.Queue(e.ctx, e.dept("HR"))
	if len(hrq.Waiting) != 2 {
		t.Fatalf("HR queue should have 2 waiting, got %d", len(hrq.Waiting))
	}
	if n := len(e.get(second.ID).Events); n < 2 {
		t.Fatalf("transfer history should be preserved as events, got %d", n)
	}

	// invalid transfers
	_, err = e.q.Transfer(e.ctx, third.ID, e.dept("IT"), e.admin)
	wantErr(t, err, domain.ErrInvalidTransfer)
	_, err = e.q.Transfer(e.ctx, third.ID, fakeID(424242), e.admin)
	wantErr(t, err, domain.ErrInvalidTransfer)
	_, err = e.q.Transfer(e.ctx, second.ID, e.dept("ACC"), e.admin) // already transferred
	wantErr(t, err, domain.ErrInvalidState)

	// paused target
	if _, err := e.q.SetPaused(e.ctx, e.dept("ACC"), true); err != nil {
		t.Fatal(err)
	}
	_, err = e.q.Transfer(e.ctx, third.ID, e.dept("ACC"), e.admin)
	wantErr(t, err, domain.ErrDepartmentPaused)
	if got := e.get(third.ID); got.Status != domain.StatusWaiting {
		t.Fatalf("failed transfer must leave the token untouched, status=%s", got.Status)
	}

	// serving tokens cannot be transferred
	serving := e.callNext("IT")
	_, err = e.q.Transfer(e.ctx, serving.ID, e.dept("ADM"), e.admin)
	wantErr(t, err, domain.ErrTokenServing)
}

// 9. Cannot call next while another token is serving.
func TestCannotCallNextWhileServing(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")
	e.newToken("IT", "")
	e.callNext("IT")
	_, err := e.q.CallNext(e.ctx, e.dept("IT"), e.admin)
	wantErr(t, err, domain.ErrServingInProgress)

	// calling a specific token is also blocked
	second := e.repo.waiting(e.dept("IT"))[0]
	_, err = e.q.CallToken(e.ctx, second.ID, e.admin)
	wantErr(t, err, domain.ErrServingInProgress)
}

func TestCallTokenMustBeHeadOfQueue(t *testing.T) {
	e := newEnv(t)
	e.newToken("IT", "")
	second := e.newToken("IT", "")
	_, err := e.q.CallToken(e.ctx, second.ID, e.admin)
	wantErr(t, err, domain.ErrNotNextInQueue)
}

func TestEstimatedWaitingTime(t *testing.T) {
	e := newEnv(t)                // default service time = 5 minutes
	e.newToken("IT", "")          // position 1 -> 0 min
	e.newToken("IT", "")          // position 2 -> 5 min
	third := e.newToken("IT", "") // 2 ahead -> 10 min
	if *third.EstimatedWaitMinutes != 10 || *third.PeopleAhead != 2 {
		t.Fatalf("estimate = %d min / %d ahead, want 10 / 2", *third.EstimatedWaitMinutes, *third.PeopleAhead)
	}
	prio := e.newToken("IT", "PRIORITY") // jumps to the front -> 0 min
	if *prio.QueuePosition != 1 || *prio.EstimatedWaitMinutes != 0 {
		t.Fatalf("priority estimate = pos %d / %d min", *prio.QueuePosition, *prio.EstimatedWaitMinutes)
	}
	if got := e.get(third.ID); *got.EstimatedWaitMinutes != 15 { // now 3 ahead
		t.Fatalf("normal token estimate after priority arrival = %d, want 15", *got.EstimatedWaitMinutes)
	}
}

func TestCompleteRules(t *testing.T) {
	e := newEnv(t)
	a := e.newToken("IT", "")
	_, err := e.q.Complete(e.ctx, a.ID, e.admin) // still WAITING
	wantErr(t, err, domain.ErrInvalidState)
	e.callNext("IT")
	e.complete(a.ID)
	_, err = e.q.Complete(e.ctx, a.ID, e.admin)
	wantErr(t, err, domain.ErrTokenCompleted)
	got := e.get(a.ID)
	if got.CompletedAt == nil || got.CalledAt == nil {
		t.Fatal("called_at and completed_at must be saved")
	}
}

func TestStaffCanOnlyManageOwnDepartment(t *testing.T) {
	e := newEnv(t)
	hr := e.dept("HR")
	staffHR := Actor{UserID: "u1", Role: domain.RoleStaff, DepartmentID: &hr}
	e.newToken("IT", "")
	_, err := e.q.CallNext(e.ctx, e.dept("IT"), staffHR)
	wantErr(t, err, domain.ErrForbidden)
	e.newToken("HR", "")
	if _, err := e.q.CallNext(e.ctx, hr, staffHR); err != nil {
		t.Fatalf("staff should manage own department: %v", err)
	}
}

func TestDashboardStatistics(t *testing.T) {
	e := newEnv(t)
	for i := 0; i < 4; i++ {
		e.newToken("IT", "")
	}
	x := e.callNext("IT")
	e.complete(x.ID)
	y := e.callNext("IT")
	if _, err := e.q.NoShow(e.ctx, y.ID, e.admin); err != nil {
		t.Fatal(err)
	}
	cancelled := e.repo.waiting(e.dept("IT"))[0]
	if _, err := e.q.Cancel(e.ctx, cancelled.ID); err != nil {
		t.Fatal(err)
	}
	e.callNext("IT")
	dash, err := e.q.Dashboard(e.ctx)
	if err != nil {
		t.Fatal(err)
	}
	tot := dash.Totals
	if tot.Completed != 1 || tot.NoShows != 1 || tot.Cancelled != 1 || tot.Serving != 1 || tot.Waiting != 1 || tot.TotalDepartments != 4 {
		t.Fatalf("unexpected totals: %+v", tot)
	}
	if tot.AvgWaitingMinutes <= 0 {
		t.Fatalf("average waiting time should be > 0, got %v", tot.AvgWaitingMinutes)
	}
}
