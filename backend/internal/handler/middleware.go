package handler

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	"smartoffice/internal/domain"
	"smartoffice/internal/service"
)

type ctxKey struct{}

func actorFrom(r *http.Request) service.Actor {
	a, _ := r.Context().Value(ctxKey{}).(service.Actor)
	return a
}

// protect requires a valid JWT whose role is one of roles.
func (a *API) protect(h http.HandlerFunc, roles ...string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		const prefix = "Bearer "
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, prefix) {
			writeError(w, domain.ErrUnauthorized)
			return
		}
		claims, err := a.JWT.Parse(strings.TrimSpace(header[len(prefix):]))
		if err != nil {
			writeError(w, domain.ErrUnauthorized)
			return
		}
		allowed := false
		for _, role := range roles {
			if claims.Role == role {
				allowed = true
			}
		}
		if !allowed {
			writeError(w, domain.ErrForbidden)
			return
		}
		actor := service.Actor{UserID: claims.Subject, Role: claims.Role, DepartmentID: claims.DepartmentID}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, actor)))
	})
}

func cors(origins string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		allow := ""
		if origins == "*" {
			allow = "*"
		} else if origin != "" {
			for _, o := range strings.Split(origins, ",") {
				if strings.TrimSpace(o) == origin {
					allow = origin
					w.Header().Add("Vary", "Origin")
				}
			}
		}
		if allow != "" {
			w.Header().Set("Access-Control-Allow-Origin", allow)
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) { s.status = code; s.ResponseWriter.WriteHeader(code) }

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s -> %d (%s)", r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
	})
}

func recoverPanic(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic: %v", rec)
				writeErrorMsg(w, http.StatusInternalServerError, "internal_error", "internal server error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
