package clock

import (
	"testing"
	"time"
)

func TestLocationIsWIB(t *testing.T) {
	loc := Location()
	if loc == nil {
		t.Fatal("Location() tidak boleh nil")
	}
	if loc.String() != "WIB" {
		t.Fatalf("nama zona harus \"WIB\", dapat %q", loc.String())
	}
}

func TestLocationOffsetPlus7(t *testing.T) {
	_, offset := time.Now().In(Location()).Zone()
	if offset != 7*3600 {
		t.Fatalf("offset WIB harus +7 jam (25200 detik), dapat %d", offset)
	}
}

func TestNowInWIBZone(t *testing.T) {
	now := Now()
	if now.Location() != Location() {
		t.Fatalf("Now() harus berada di zona Location(), dapat %q", now.Location())
	}
	// Sanity: Now() WIB tidak boleh menyimpang jauh dari time.Now().
	diff := now.Sub(time.Now())
	if diff < -time.Minute || diff > time.Minute {
		t.Fatalf("Now() menyimpang terlalu jauh dari waktu nyata: %v", diff)
	}
}
