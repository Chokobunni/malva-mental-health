package payment

import (
	"crypto/sha512"
	"encoding/hex"
	"strings"
	"testing"
)

// hashRaw menghitung SHA-512 hex dari sebuah string mentah memakai primitif
// stdlib langsung — sengaja TIDAK memakai MidtransSignature, supaya test di
// bawah benar-benar independen dari implementasi yang diuji.
func hashRaw(s string) string {
	sum := sha512.Sum512([]byte(s))
	return hex.EncodeToString(sum[:])
}

// ============================================================
// GOLDEN TEST SIGNATURE MIDTRANS — LINTAS IMPLEMENTASI
//
// Tujuan: kunci URUTAN & ISI string yang di-hash, bukan sekadar "signature
// yang kita hitung diterima oleh kode kita sendiri". Test lama
// (TestMidtransSignatureValid) membandingkan kode dengan dirinya sendiri,
// sehingga salah tafsir urutan field (mis. gross_amount sebelum status_code)
// akan TETAP lulus padahal produksi menolak 100% notifikasi Midtrans.
//
// Semua nilai harapan di bawah dihitung DI LUAR kode Go, dengan dua alat
// independen yang keduanya sepakat:
//
//	python3 -c 'import hashlib;print(hashlib.sha512(b"...").hexdigest())'
//	printf '%s' '...' | sha512sum
//
// String yang di-hash adalah gabungan tanpa pemisah:
//
//	order_id + status_code + gross_amount + server_key
//
// sesuai dokumentasi Midtrans dan implementasi gateway.
// ============================================================

// goldenVectors adalah vektor uji yang dihitung independen (python hashlib /
// sha512sum), BUKAN dari MidtransSignature.
var goldenVectors = []struct {
	name       string
	orderID    string
	statusCode string
	grossAmt   string
	serverKey  string
	want       string
}{
	{
		// Vektor 1: gross_amount berkoma desimal (bentuk asli Midtrans).
		name:       "gross desimal 150000.00",
		orderID:    "TXN-20261020100000-123456",
		statusCode: "200",
		grossAmt:   "150000.00",
		serverKey:  "SB-Mid-server-testkey",
		want:       "b174f8a6ccb80241fc111f571c1eb221154e697de7d70ee48055489f60f81089dde6a171140c465559e5476981b5c7e2f9cf643e8672739406f1fe0faeb053a1",
	},
	{
		// Vektor 2: gross_amount ANGKA BULAT tanpa desimal — memastikan kita
		// tidak "menormalkan" angka (Midtrans memakai apa adanya dari payload,
		// sehingga "50000" dan "50000.00" menghasilkan signature BERBEDA).
		name:       "gross bulat 50000",
		orderID:    "order-abc-1",
		statusCode: "200",
		grossAmt:   "50000",
		serverKey:  "SB-Mid-server-golden",
		want:       "56396be17eb92073f5f11f5b4a1e5606ad8c8c5232fb62df81b8f8b4ed6553d9e8debc30703a96720f4739d4c29b2432a1ee3cf3ab934e6f1cc6d1a25330d4be",
	},
	{
		// Vektor 3: order_id dengan tanda hubung/underscore + status_code 201
		// (capture kartu) — memastikan tidak ada escaping/trimming tersembunyi.
		name:       "order_id berkarakter khusus + status 201",
		orderID:    "ORDER-WITH-DASH_20261020",
		statusCode: "201",
		grossAmt:   "1250000.00",
		serverKey:  "SB-Mid-server-golden",
		want:       "d02d0955a884cfc542e4606c1c9fa91841d7764df12ca01facf4001dae701af7c10b4f652cf951b0d390f5a6d4d8f94a10d62820566049272820fb2e157ee785",
	},
}

// TestMidtransSignatureGoldenVectors membandingkan MidtransSignature dengan
// vektor SHA-512 yang dihitung di luar Go.
func TestMidtransSignatureGoldenVectors(t *testing.T) {
	for _, v := range goldenVectors {
		t.Run(v.name, func(t *testing.T) {
			got := MidtransSignature(v.orderID, v.statusCode, v.grossAmt, v.serverKey)
			if got != v.want {
				t.Fatalf("signature tidak cocok dengan vektor independen\n order_id=%q status_code=%q gross=%q\n got  = %s\n want = %s",
					v.orderID, v.statusCode, v.grossAmt, got, v.want)
			}
			// Panjang hex SHA-512 selalu 128 karakter.
			if len(got) != 128 {
				t.Fatalf("panjang signature = %d, mau 128", len(got))
			}
			if got != strings.ToLower(got) {
				t.Fatalf("signature harus hex huruf kecil: %s", got)
			}
		})
	}
}

// TestMidtransSignatureGoldenRejectsWrongFieldOrder membuktikan golden test di
// atas memang SENSITIF terhadap urutan field: setiap urutan lain menghasilkan
// digest berbeda. Tanpa ini, golden test bisa "lulus" karena kebetulan.
func TestMidtransSignatureGoldenRejectsWrongFieldOrder(t *testing.T) {
	const (
		orderID    = "TXN-20261020100000-123456"
		statusCode = "200"
		grossAmt   = "150000.00"
		serverKey  = "SB-Mid-server-testkey"
	)
	correct := goldenVectors[0].want

	wrong := map[string]string{
		"order+gross+status+key": orderID + grossAmt + statusCode + serverKey,
		"gross+status+order+key": grossAmt + statusCode + orderID + serverKey,
		"order+status+key+gross": orderID + statusCode + serverKey + grossAmt,
		"key+order+status+gross": serverKey + orderID + statusCode + grossAmt,
		"tanpa server key":       orderID + statusCode + grossAmt,
	}
	for name, concat := range wrong {
		if hashRaw(concat) == correct {
			t.Fatalf("%s: urutan salah menghasilkan digest SAMA dengan yang benar — golden test tidak akan menangkap salah tafsir", name)
		}
	}
	// gross "50000" vs "50000.00" harus berbeda (tidak ada normalisasi angka).
	if MidtransSignature("order-abc-1", "200", "50000", "SB-Mid-server-golden") ==
		MidtransSignature("order-abc-1", "200", "50000.00", "SB-Mid-server-golden") {
		t.Fatal("gross \"50000\" dan \"50000.00\" menghasilkan signature sama; implementasi menormalkan angka padahal Midtrans tidak")
	}
}

// TestMidtransVerifySignatureGoldenEvent memastikan VerifySignature (jalur yang
// dipakai handler webhook) menerima notifikasi yang signature-nya berasal dari
// vektor independen — bukan dari fungsi yang sama.
func TestMidtransVerifySignatureGoldenEvent(t *testing.T) {
	for _, v := range goldenVectors {
		t.Run(v.name, func(t *testing.T) {
			gw := NewMidtransGateway(MidtransConfig{ServerKey: v.serverKey})
			evt := WebhookEvent{
				OrderID:     v.orderID,
				StatusCode:  v.statusCode,
				GrossAmount: v.grossAmt,
				Signature:   v.want, // <- dari vektor, bukan dari MidtransSignature
			}
			if !gw.VerifySignature(evt) {
				t.Fatal("signature dari vektor independen ditolak VerifySignature")
			}
			// Signature huruf besar (Midtrans tidak menjamin casing) harus tetap
			// diterima karena kita menormalkan ke huruf kecil.
			evt.Signature = strings.ToUpper(v.want)
			if !gw.VerifySignature(evt) {
				t.Fatal("signature hex huruf besar seharusnya diterima")
			}
			// Server key lain -> tolak.
			other := NewMidtransGateway(MidtransConfig{ServerKey: v.serverKey + "x"})
			if other.VerifySignature(evt) {
				t.Fatal("server key berbeda seharusnya menolak")
			}
		})
	}
}
