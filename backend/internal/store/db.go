package store

import (
	"context"
	"database/sql"

	"malva/backend/internal/clock"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/stdlib"
)

// OpenSQL membuka *sql.DB lewat driver pgx dengan dekode timestamptz dipaksa
// ke zona WIB.
//
// Latar belakang: pgx v5 men-decode timestamptz memakai time.Unix(...) sehingga
// hasil scan bertanda zona lokal proses Go (di VM Azure = UTC). Akibatnya
// json.Marshal mengeluarkan "...Z" dan klien melihat jam mundur 7 jam. Dengan
// mendaftarkan TimestamptzCodec ber-ScanLocation WIB, semua nilai timestamptz
// keluar dalam offset +07:00.
//
// Session timezone juga diset "Asia/Jakarta" agar now()/::text di sisi DB ikut
// WIB. Koneksi tetap lazy seperti sql.Open; pemanggil tetap wajib Ping.
func OpenSQL(dsn string) (*sql.DB, error) {
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	if cfg.RuntimeParams == nil {
		cfg.RuntimeParams = map[string]string{}
	}
	cfg.RuntimeParams["timezone"] = "Asia/Jakarta"
	loc := clock.Location()
	// OptionAfterConnect memberi akses ke *pgx.Conn (bukan *pgconn.PgConn),
	// sehingga TypeMap-nya bisa didaftari codec kustom. Pendekatan
	// cfg.AfterConnect tidak bisa dipakai: field itu milik pgconn.Config
	// (bertipe *pgconn.PgConn) yang tidak punya TypeMap.
	return stdlib.OpenDB(*cfg, stdlib.OptionAfterConnect(func(_ context.Context, c *pgx.Conn) error {
		c.TypeMap().RegisterType(&pgtype.Type{
			Name:  "timestamptz",
			OID:   pgtype.TimestamptzOID,
			Codec: &pgtype.TimestamptzCodec{ScanLocation: loc},
		})
		return nil
	})), nil
}
