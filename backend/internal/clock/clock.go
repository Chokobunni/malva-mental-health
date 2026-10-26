// Package clock menyediakan sumber waktu terpusat untuk zona WIB
// (Asia/Jakarta, UTC+7). Semua timestamp yang disimpan ke database atau
// dikirim di DTO sebaiknya memakai clock.Now(), bukan time.Now() langsung.
package clock

import "time"

// wib adalah zona WIB tetap (UTC+7). Sengaja memakai FixedZone, bukan
// time.LoadLocation("Asia/Jakarta"), karena LoadLocation membutuhkan tzdata
// yang bisa tidak tersedia di Windows atau image minimal (scratch).
// WIB tidak menerapkan DST, sehingga offset tetap selalu benar.
var wib = time.FixedZone("WIB", 7*3600)

// Location mengembalikan lokasi zona WIB yang dipakai bersama.
func Location() *time.Location {
	return wib
}

// Now mengembalikan waktu sekarang dalam zona WIB.
func Now() time.Time {
	return time.Now().In(Location())
}
