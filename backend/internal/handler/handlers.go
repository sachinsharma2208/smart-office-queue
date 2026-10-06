package handler

import (
	"net/http"

	"smartoffice/internal/service"
)

// ---- auth

func (a *API) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	res, err := a.Auth.Login(r.Context(), in.Email, in.Password)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// ---- departments

func (a *API) listDepartments(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.ListDepartments(r.Context())
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (a *API) getDepartment(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.GetDepartment(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (a *API) pause(w http.ResponseWriter, r *http.Request)  { a.setPaused(w, r, true) }
func (a *API) resume(w http.ResponseWriter, r *http.Request) { a.setPaused(w, r, false) }

func (a *API) setPaused(w http.ResponseWriter, r *http.Request, paused bool) {
	v, err := a.Queue.SetPaused(r.Context(), r.PathValue("id"), paused)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// ---- tokens

func (a *API) createToken(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DepartmentID string `json:"department_id"`
		Priority     string `json:"priority"` // "NORMAL" (default) or "PRIORITY"
	}
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	v, err := a.Queue.CreateToken(r.Context(), in.DepartmentID, in.Priority)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, v)
}

func (a *API) getToken(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.GetToken(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (a *API) cancelToken(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.Cancel(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// tokenAction adapts a service method with the (ctx, id, actor) shape.
func tokenAction(fn func(r *http.Request, id string, actor service.Actor) (*service.TokenView, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		v, err := fn(r, r.PathValue("id"), actorFrom(r))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, v)
	}
}

func (a *API) callToken(w http.ResponseWriter, r *http.Request) {
	tokenAction(func(r *http.Request, id string, actor service.Actor) (*service.TokenView, error) {
		return a.Queue.CallToken(r.Context(), id, actor)
	})(w, r)
}

func (a *API) complete(w http.ResponseWriter, r *http.Request) {
	tokenAction(func(r *http.Request, id string, actor service.Actor) (*service.TokenView, error) {
		return a.Queue.Complete(r.Context(), id, actor)
	})(w, r)
}

func (a *API) noShow(w http.ResponseWriter, r *http.Request) {
	tokenAction(func(r *http.Request, id string, actor service.Actor) (*service.TokenView, error) {
		return a.Queue.NoShow(r.Context(), id, actor)
	})(w, r)
}

func (a *API) transfer(w http.ResponseWriter, r *http.Request) {
	var in struct {
		TargetDepartmentID string `json:"target_department_id"`
	}
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	v, err := a.Queue.Transfer(r.Context(), r.PathValue("id"), in.TargetDepartmentID, actorFrom(r))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// ---- queues

func (a *API) getQueue(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.Queue(r.Context(), r.PathValue("departmentId"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (a *API) callNext(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.CallNext(r.Context(), r.PathValue("departmentId"), actorFrom(r))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

// ---- dashboard

func (a *API) dashboard(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.Dashboard(r.Context())
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (a *API) departmentDashboard(w http.ResponseWriter, r *http.Request) {
	v, err := a.Queue.DepartmentDashboard(r.Context(), r.PathValue("departmentId"), actorFrom(r))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}
