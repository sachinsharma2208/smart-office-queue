package service

import (
	"context"
	"fmt"
	"sort"
	"time"

	"smartoffice/internal/domain"
	"smartoffice/internal/store"
)

// fakeRepo is a tiny in-memory store.Repo used to test the business rules
// without a database. Ordering rules mirror the SQL in store/postgres.
type fakeRepo struct {
	depts   []*domain.Department
	tokens  []*domain.Token
	events  []domain.QueueEvent
	seq     map[string]int
	counter int
}

var _ store.Repo = (*fakeRepo)(nil)

func newFakeRepo() *fakeRepo {
	f := &fakeRepo{seq: map[string]int{}}
	for i, d := range []struct{ name, code string }{{"IT Support", "IT"}, {"HR", "HR"}, {"Accounts", "ACC"}, {"Administration", "ADM"}} {
		f.depts = append(f.depts, &domain.Department{
			ID: fakeID(1000 + i), Name: d.name, Code: d.code, DefaultServiceMinutes: 5,
		})
	}
	return f
}

func fakeID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012d", n) }

func (f *fakeRepo) WithTx(_ context.Context, fn func(store.Repo) error) error { return fn(f) }

func (f *fakeRepo) dept(id string) *domain.Department {
	for _, d := range f.depts {
		if d.ID == id {
			return d
		}
	}
	return nil
}

func (f *fakeRepo) ListDepartments(context.Context) ([]domain.Department, error) {
	out := []domain.Department{}
	for _, d := range f.depts {
		out = append(out, *d)
	}
	return out, nil
}

func (f *fakeRepo) GetDepartment(_ context.Context, id string, _ bool) (*domain.Department, error) {
	if d := f.dept(id); d != nil {
		c := *d
		return &c, nil
	}
	return nil, domain.ErrNotFound
}

func (f *fakeRepo) SetDepartmentPaused(_ context.Context, id string, paused bool) error {
	d := f.dept(id)
	if d == nil {
		return domain.ErrNotFound
	}
	d.IsPaused = paused
	return nil
}

func (f *fakeRepo) NextSequence(_ context.Context, id string) (int, error) {
	f.seq[id]++
	return f.seq[id], nil
}

func (f *fakeRepo) DepartmentStats(_ context.Context, id string) (domain.DeptStats, error) {
	var st domain.DeptStats
	for _, t := range f.tokens {
		if t.DepartmentID != id {
			continue
		}
		switch t.Status {
		case domain.StatusWaiting:
			st.Waiting++
		case domain.StatusServing:
			st.Serving++
		case domain.StatusCompleted:
			st.Completed++
		case domain.StatusCancelled:
			st.Cancelled++
		}
		st.NoShows += t.NoShowCount
		if t.CalledAt != nil {
			st.CalledCount++
			st.TotalWaitSeconds += t.CalledAt.Sub(t.QueueEnteredAt).Seconds()
			if t.Status == domain.StatusCompleted && t.CompletedAt != nil {
				st.TimedCompleted++
				st.ServiceSeconds += t.CompletedAt.Sub(*t.CalledAt).Seconds()
			}
		}
	}
	return st, nil
}

func (f *fakeRepo) CreateToken(_ context.Context, t *domain.Token) error {
	f.counter++
	t.ID = fakeID(f.counter)
	c := *t
	f.tokens = append(f.tokens, &c)
	return nil
}

func (f *fakeRepo) tok(id string) *domain.Token {
	for _, t := range f.tokens {
		if t.ID == id {
			return t
		}
	}
	return nil
}

func (f *fakeRepo) GetToken(_ context.Context, id string) (*domain.Token, error) {
	if t := f.tok(id); t != nil {
		c := *t
		return &c, nil
	}
	return nil, domain.ErrNotFound
}

func (f *fakeRepo) UpdateToken(_ context.Context, t *domain.Token) error {
	cur := f.tok(t.ID)
	if cur == nil {
		return domain.ErrNotFound
	}
	if t.Status == domain.StatusServing { // emulate uq_one_serving_per_department
		for _, o := range f.tokens {
			if o.DepartmentID == t.DepartmentID && o.Status == domain.StatusServing && o.ID != t.ID {
				return domain.ErrServingInProgress
			}
		}
	}
	*cur = *t
	return nil
}

func (f *fakeRepo) GetServingToken(_ context.Context, deptID string) (*domain.Token, error) {
	for _, t := range f.tokens {
		if t.DepartmentID == deptID && t.Status == domain.StatusServing {
			c := *t
			return &c, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (f *fakeRepo) waiting(deptID string) []domain.Token {
	var w []domain.Token
	for _, t := range f.tokens {
		if t.DepartmentID == deptID && t.Status == domain.StatusWaiting {
			w = append(w, *t)
		}
	}
	sort.SliceStable(w, func(i, j int) bool {
		a, b := w[i], w[j]
		if a.Priority != b.Priority {
			return a.Priority > b.Priority
		}
		if !a.QueueEnteredAt.Equal(b.QueueEnteredAt) {
			return a.QueueEnteredAt.Before(b.QueueEnteredAt)
		}
		return a.SequenceNo < b.SequenceNo
	})
	return w
}

func (f *fakeRepo) NextEligibleToken(_ context.Context, deptID string) (*domain.Token, error) {
	w := f.waiting(deptID)
	if len(w) == 0 {
		return nil, domain.ErrNotFound
	}
	return &w[0], nil
}

func (f *fakeRepo) ListWaiting(_ context.Context, deptID string) ([]domain.Token, error) {
	return f.waiting(deptID), nil
}

func (f *fakeRepo) QueuePosition(_ context.Context, t *domain.Token) (int, error) {
	for i, w := range f.waiting(t.DepartmentID) {
		if w.ID == t.ID {
			return i + 1, nil
		}
	}
	return 0, domain.ErrNotFound
}

func (f *fakeRepo) GetTransferTarget(_ context.Context, id string) (*domain.Token, error) {
	for _, t := range f.tokens {
		if t.TransferredFromTokenID != nil && *t.TransferredFromTokenID == id {
			c := *t
			return &c, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (f *fakeRepo) AddEvent(_ context.Context, tokenID, typ string, meta map[string]any) error {
	f.events = append(f.events, domain.QueueEvent{ID: int64(len(f.events) + 1), TokenID: tokenID, EventType: typ, Metadata: meta, CreatedAt: time.Now()})
	return nil
}

func (f *fakeRepo) ListEvents(_ context.Context, tokenID string) ([]domain.QueueEvent, error) {
	out := []domain.QueueEvent{}
	for _, e := range f.events {
		if e.TokenID == tokenID {
			out = append(out, e)
		}
	}
	return out, nil
}

func (f *fakeRepo) GetUserByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}
func (f *fakeRepo) CreateUser(context.Context, *domain.User) error { return nil }
