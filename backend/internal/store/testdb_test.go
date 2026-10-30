package store

import (
	"os"
	"testing"
)

// testDatabaseDSN mengembalikan DSN Postgres untuk seluruh integration test
// paket store, sehingga pembacaan env tidak lagi diduplikasi di tiap berkas.
//
// Urutan sumber:
//  1. MALVA_TEST_DATABASE_URL — variabel resmi untuk test (disetel CI pada
//     .github/workflows/backend-ci.yml).
//  2. MALVA_DATABASE_URL — fallback agar test tetap jalan bila hanya variabel
//     aplikasi yang tersedia.
//
// Bila keduanya kosong, test di-SKIP (bukan gagal): test store butuh Postgres
// nyata, dan mesin pengembang tanpa DB harus tetap bisa menjalankan paket ini.
func testDatabaseDSN(t *testing.T) string {
	t.Helper()
	if dsn := os.Getenv("MALVA_TEST_DATABASE_URL"); dsn != "" {
		return dsn
	}
	if dsn := os.Getenv("MALVA_DATABASE_URL"); dsn != "" {
		return dsn
	}
	t.Skip("butuh Postgres: set MALVA_TEST_DATABASE_URL")
	return ""
}
