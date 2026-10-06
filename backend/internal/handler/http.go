// Package handler is the HTTP layer: routing, JSON, auth middleware and
// error mapping. It contains no business rules - those live in service.
package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"

	"smartoffice/internal/domain"
)

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// errorMap converts business errors into HTTP responses (first match wins).
var errorMap = []struct {
	err    error
	status int
	code   string
}{
	{domain.ErrValidation, http.StatusBadRequest, "validation_error"},
	{domain.ErrInvalidTransfer, http.StatusBadRequest, "invalid_transfer"},
	{domain.ErrUnauthorized, http.StatusUnauthorized, "unauthorized"},
	{domain.ErrForbidden, http.StatusForbidden, "forbidden"},
	{domain.ErrNotFound, http.StatusNotFound, "not_found"},
	{domain.ErrQueueEmpty, http.StatusNotFound, "queue_empty"},
	{domain.ErrDepartmentPaused, http.StatusConflict, "department_paused"},
	{domain.ErrServingInProgress, http.StatusConflict, "serving_in_progress"},
	{domain.ErrTokenServing, http.StatusConflict, "token_serving"},
	{domain.ErrTokenCompleted, http.StatusConflict, "token_completed"},
	{domain.ErrTokenCancelled, http.StatusConflict, "token_cancelled"},
	{domain.ErrInvalidState, http.StatusConflict, "invalid_state"},
	{domain.ErrNotNextInQueue, http.StatusConflict, "not_next_in_queue"},
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v != nil {
		if err := json.NewEncoder(w).Encode(v); err != nil {
			log.Printf("encode response: %v", err)
		}
	}
}

func writeErrorMsg(w http.ResponseWriter, status int, code, msg string) {
	var b errorBody
	b.Error.Code, b.Error.Message = code, msg
	writeJSON(w, status, b)
}

// writeError maps err to a status code. Unknown errors (database failures,
// bugs) are logged but never leaked to the client.
func writeError(w http.ResponseWriter, err error) {
	for _, m := range errorMap {
		if errors.Is(err, m.err) {
			writeErrorMsg(w, m.status, m.code, err.Error())
			return
		}
	}
	log.Printf("internal error: %v", err)
	writeErrorMsg(w, http.StatusInternalServerError, "internal_error", "internal server error")
}

// decodeJSON parses a JSON body strictly (unknown fields rejected, 1 MiB cap).
// An empty body is allowed and leaves dst untouched.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("%w: malformed JSON body", domain.ErrValidation)
	}
	return nil
}
