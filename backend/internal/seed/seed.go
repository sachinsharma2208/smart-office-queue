// Package seed creates the demo staff/admin accounts. Passwords come from the
// SEED_PASSWORD environment variable - they are never stored in source code.
package seed

import (
	"context"
	"errors"
	"log"

	"smartoffice/internal/auth"
	"smartoffice/internal/domain"
	"smartoffice/internal/store"
)

type account struct {
	name, email, role, deptCode string
}

var accounts = []account{
	{"Admin User", "admin@smartoffice.local", domain.RoleAdmin, ""},
	{"IT Staff", "it.staff@smartoffice.local", domain.RoleStaff, "IT"},
	{"HR Staff", "hr.staff@smartoffice.local", domain.RoleStaff, "HR"},
	{"Accounts Staff", "accounts.staff@smartoffice.local", domain.RoleStaff, "ACC"},
	{"Administration Staff", "admin.staff@smartoffice.local", domain.RoleStaff, "ADM"},
}

// Run inserts any missing demo user. It is idempotent.
func Run(ctx context.Context, repo store.Repo, password string) error {
	depts, err := repo.ListDepartments(ctx)
	if err != nil {
		return err
	}
	byCode := map[string]string{}
	for _, d := range depts {
		byCode[d.Code] = d.ID
	}
	hash, err := auth.HashPassword(password)
	if err != nil {
		return err
	}
	for _, a := range accounts {
		if _, err := repo.GetUserByEmail(ctx, a.email); err == nil {
			continue
		} else if !errors.Is(err, domain.ErrNotFound) {
			return err
		}
		u := &domain.User{Name: a.name, Email: a.email, PasswordHash: hash, Role: a.role}
		if a.deptCode != "" {
			id := byCode[a.deptCode]
			u.DepartmentID = &id
		}
		if err := repo.CreateUser(ctx, u); err != nil {
			return err
		}
		log.Printf("seeded user %s (%s)", a.email, a.role)
	}
	return nil
}
