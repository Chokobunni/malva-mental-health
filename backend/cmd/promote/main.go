// Command promote mengangkat satu pengguna menjadi admin berdasarkan email.
// Pemakaian: MALVA_DATABASE_URL=... go run ./cmd/promote user@example.com
package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "promote gagal:", err)
		os.Exit(1)
	}
}

func run() error {
	if len(os.Args) != 2 || strings.TrimSpace(os.Args[1]) == "" {
		return fmt.Errorf("pemakaian: promote <email>")
	}
	email := strings.ToLower(strings.TrimSpace(os.Args[1]))
	dbURL := os.Getenv("MALVA_DATABASE_URL")
	if dbURL == "" {
		return fmt.Errorf("MALVA_DATABASE_URL wajib diisi")
	}
	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		return err
	}
	defer func() { _ = db.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	res, err := db.ExecContext(ctx,
		`UPDATE users SET role = 'admin'::user_role, updated_at = now() WHERE lower(email) = $1 AND disabled_at IS NULL`,
		email)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return fmt.Errorf("pengguna dengan email %s tidak ditemukan", email)
	}
	fmt.Printf("OK: %s sekarang admin.\n", email)
	return nil
}
