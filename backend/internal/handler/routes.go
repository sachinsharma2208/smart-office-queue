package handler

import (
	"net/http"

	"smartoffice/internal/auth"
	"smartoffice/internal/domain"
	"smartoffice/internal/service"
)

// API wires HTTP routes to the services.
type API struct {
	Queue       *service.Queue
	Auth        *auth.Service
	JWT         *auth.Manager
	CORSOrigins string
}

var (
	staffOrAdmin = []string{domain.RoleStaff, domain.RoleAdmin}
	adminOnly    = []string{domain.RoleAdmin}
)

// Routes uses Go 1.22 method+path patterns (r.PathValue).
func (a *API) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// --- public (visitors) ---
	mux.HandleFunc("POST /api/auth/login", a.login)
	mux.HandleFunc("GET /api/departments", a.listDepartments)
	mux.HandleFunc("GET /api/departments/{id}", a.getDepartment)
	mux.HandleFunc("POST /api/tokens", a.createToken)
	mux.HandleFunc("GET /api/tokens/{id}", a.getToken)
	mux.HandleFunc("DELETE /api/tokens/{id}", a.cancelToken)
	mux.HandleFunc("POST /api/tokens/{id}/cancel", a.cancelToken)
	mux.HandleFunc("GET /api/queues/{departmentId}", a.getQueue)

	// --- staff / admin ---
	mux.Handle("POST /api/queues/{departmentId}/call-next", a.protect(a.callNext, staffOrAdmin...))
	mux.Handle("POST /api/tokens/{id}/call", a.protect(a.callToken, staffOrAdmin...))
	mux.Handle("POST /api/tokens/{id}/complete", a.protect(a.complete, staffOrAdmin...))
	mux.Handle("POST /api/tokens/{id}/no-show", a.protect(a.noShow, staffOrAdmin...))
	mux.Handle("POST /api/tokens/{id}/transfer", a.protect(a.transfer, staffOrAdmin...))
	mux.Handle("GET /api/dashboard/{departmentId}", a.protect(a.departmentDashboard, staffOrAdmin...))

	// --- admin only ---
	mux.Handle("POST /api/departments/{id}/pause", a.protect(a.pause, adminOnly...))
	mux.Handle("POST /api/departments/{id}/resume", a.protect(a.resume, adminOnly...))
	mux.Handle("GET /api/dashboard", a.protect(a.dashboard, adminOnly...))

	mux.HandleFunc("/api/", func(w http.ResponseWriter, _ *http.Request) {
		writeErrorMsg(w, http.StatusNotFound, "not_found", "endpoint not found")
	})

	return recoverPanic(logging(cors(a.CORSOrigins, mux)))
}
