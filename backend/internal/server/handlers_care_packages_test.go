package server

import (
	"testing"
	"time"

	"malva/backend/internal/clock"
)

// TestParseWIBDateTimeInterpretsAsWIB memastikan wall-clock tanpa offset dari
// klien (format API `yyyy-MM-ddTHH:mm`) ditafsirkan sebagai WIB, bukan UTC.
// Bila salah, jadwal sesi bergeser 7 jam.
func TestParseWIBDateTimeInterpretsAsWIB(t *testing.T) {
	got, err := parseWIBDateTime("2026-11-01T10:00")
	if err != nil {
		t.Fatalf("parseWIBDateTime error: %v", err)
	}
	if got.Hour() != 10 || got.Minute() != 0 {
		t.Errorf("jam = %02d:%02d, mau 10:00 WIB", got.Hour(), got.Minute())
	}
	if _, offset := got.Zone(); offset != 7*3600 {
		t.Errorf("offset = %d detik, mau %d (+07:00)", offset, 7*3600)
	}
	if name, _ := got.Zone(); name != "WIB" && name != "Asia/Jakarta" {
		t.Errorf("nama zona = %q, mau WIB/Asia/Jakarta", name)
	}
	if got.Location() != clock.Location() {
		t.Errorf("lokasi = %v, mau clock.Location() (WIB)", got.Location())
	}

	// Instant yang sama dengan offset eksplisit harus identik.
	withOffset, err := parseWIBDateTime("2026-11-01T10:00:00+07:00")
	if err != nil {
		t.Fatalf("parseWIBDateTime(+07:00) error: %v", err)
	}
	if !withOffset.Equal(got) {
		t.Errorf("instant +07:00 = %v, mau sama dengan %v", withOffset, got)
	}
	if h := withOffset.In(clock.Location()).Hour(); h != 10 {
		t.Errorf("jam dalam WIB = %d, mau 10", h)
	}
}

// TestParseWIBDateTimeRejectsGarbage memastikan input tidak valid tidak diam-diam
// dianggap waktu nol (yang akan lolos ke database sebagai jadwal tahun 1).
func TestParseWIBDateTimeRejectsGarbage(t *testing.T) {
	for _, in := range []string{"", "  ", "besok pagi", "2026-13-40T99:99"} {
		if got, err := parseWIBDateTime(in); err == nil {
			t.Errorf("parseWIBDateTime(%q) harus error, dapat %v", in, got)
		}
	}
}

// TestParseWIBDateTimeAcceptsSpaceSeparator memastikan format dari dialog
// (spasi, bukan T) juga dipahami sebagai WIB.
func TestParseWIBDateTimeAcceptsSpaceSeparator(t *testing.T) {
	got, err := parseWIBDateTime("2026-11-01 10:00")
	if err != nil {
		t.Fatalf("parseWIBDateTime error: %v", err)
	}
	want := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())
	if !got.Equal(want) {
		t.Errorf("hasil = %v, mau %v", got, want)
	}
}
