// Package migrations embeds the SQL migration files so the server can apply
// them on startup without any external tooling.
package migrations

import "embed"

//go:embed *.up.sql
var FS embed.FS
