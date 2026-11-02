package notify

import "testing"

// Unit test murni (tanpa DB/FCM) untuk konstruksi CollapseKey notifikasi.
//
// Regresi yang dijaga: dua pengiriman untuk peristiwa yang sama (mis. pengingat
// sesi yang di-retry atau ganda karena beberapa token) harus memakai collapse
// key yang sama agar perangkat menampilkan SATU baris, bukan menumpuk.
func TestCollapseKeyFor(t *testing.T) {
	cases := []struct {
		name string
		data map[string]string
		want string
	}{
		{
			name: "kind dan session_id",
			data: map[string]string{"kind": "session_reminder", "session_id": "abc-123"},
			want: "session_reminder:abc-123",
		},
		{
			name: "kind saja tanpa session_id",
			data: map[string]string{"kind": "medication_reminder"},
			want: "medication_reminder",
		},
		{
			name: "session_id kosong jatuh ke kind",
			data: map[string]string{"kind": "session_scheduled", "session_id": "  "},
			want: "session_scheduled",
		},
		{
			name: "tanpa kind -> kosong (tidak collapse)",
			data: map[string]string{"session_id": "abc-123"},
			want: "",
		},
		{
			name: "data nil -> kosong",
			data: nil,
			want: "",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := collapseKeyFor(c.data); got != c.want {
				t.Fatalf("collapseKeyFor(%v) = %q, mau %q", c.data, got, c.want)
			}
		})
	}
}

// TestIsDeadTokenError memastikan deteksi token basi: nil -> false, dan galat
// teks "not-registered"/"invalid-argument" -> true sebagai fallback.
func TestIsDeadTokenError(t *testing.T) {
	if isDeadTokenError(nil) {
		t.Fatal("nil bukan dead token error")
	}
	deadTexts := []string{
		"registration-token-not-registered",
		"Requested entity was not found. invalid-argument",
	}
	for _, s := range deadTexts {
		if !isDeadTokenError(errString(s)) {
			t.Errorf("galat %q seharusnya dianggap dead token", s)
		}
	}
	if isDeadTokenError(errString("internal server error")) {
		t.Fatal("galat server biasa bukan dead token")
	}
}

type errString string

func (e errString) Error() string { return string(e) }
