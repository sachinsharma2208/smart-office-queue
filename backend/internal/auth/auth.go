// Package auth handles password hashing, JWT issuing/parsing and login.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"smartoffice/internal/domain"
	"smartoffice/internal/store"
)

func HashPassword(p string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(p), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(hash, p string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(p)) == nil
}

// Claims are the JWT payload. Subject holds the user id.
type Claims struct {
	Role         string  `json:"role"`
	DepartmentID *string `json:"dept,omitempty"`
	jwt.RegisteredClaims
}

type Manager struct {
	secret []byte
	ttl    time.Duration
}

func NewManager(secret string, ttl time.Duration) *Manager {
	return &Manager{secret: []byte(secret), ttl: ttl}
}

func (m *Manager) Issue(u *domain.User) (string, time.Time, error) {
	exp := time.Now().Add(m.ttl)
	claims := Claims{
		Role: u.Role, DepartmentID: u.DepartmentID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject: u.ID, ExpiresAt: jwt.NewNumericDate(exp), IssuedAt: jwt.NewNumericDate(time.Now()),
		},
	}
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
	return s, exp, err
}

// Parse validates signature (HS256 only) and expiry.
func (m *Manager) Parse(token string) (*Claims, error) {
	c := &Claims{}
	t, err := jwt.ParseWithClaims(token, c, func(*jwt.Token) (any, error) { return m.secret, nil },
		jwt.WithValidMethods([]string{"HS256"}))
	if err != nil || !t.Valid || c.Subject == "" {
		return nil, domain.ErrUnauthorized
	}
	return c, nil
}

type UserInfo struct {
	ID             string  `json:"id"`
	Name           string  `json:"name"`
	Email          string  `json:"email"`
	Role           string  `json:"role"`
	DepartmentID   *string `json:"department_id"`
	DepartmentName *string `json:"department_name"`
}

type LoginResult struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	User      UserInfo  `json:"user"`
}

type Service struct {
	repo store.Repo
	jwt  *Manager
}

func NewService(repo store.Repo, m *Manager) *Service { return &Service{repo: repo, jwt: m} }

// dummyHash makes unknown-email logins cost the same as wrong-password ones.
var dummyHash, _ = HashPassword("not-a-real-password")

func (s *Service) Login(ctx context.Context, email, password string) (*LoginResult, error) {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		return nil, fmt.Errorf("%w: email and password are required", domain.ErrValidation)
	}
	invalid := fmt.Errorf("%w: invalid email or password", domain.ErrUnauthorized)

	u, err := s.repo.GetUserByEmail(ctx, email)
	if errors.Is(err, domain.ErrNotFound) {
		CheckPassword(dummyHash, password)
		return nil, invalid
	}
	if err != nil {
		return nil, err
	}
	if !CheckPassword(u.PasswordHash, password) {
		return nil, invalid
	}
	tok, exp, err := s.jwt.Issue(u)
	if err != nil {
		return nil, err
	}
	info := UserInfo{ID: u.ID, Name: u.Name, Email: u.Email, Role: u.Role, DepartmentID: u.DepartmentID}
	if u.DepartmentID != nil {
		if d, err := s.repo.GetDepartment(ctx, *u.DepartmentID, false); err == nil {
			info.DepartmentName = &d.Name
		}
	}
	return &LoginResult{Token: tok, ExpiresAt: exp, User: info}, nil
}
