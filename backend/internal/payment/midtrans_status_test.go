package payment

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// ============================================================
// FetchStatus — CEK STATUS LANGSUNG KE API MIDTRANS
//
// Endpoint status berada di host BERBEDA dari Snap (`api.*`, bukan `app.*`)
// Respons berasal dari API terautentikasi; signature webhook bukan syarat GET.
// ============================================================

const statusTestKey = "SB-Mid-server-STATUSTESTKEY"

// newStatusServer membuat httptest yang meniru `GET /v2/{order_id}/status`.
func newStatusServer(t *testing.T, orderID, statusCode, gross, txStatus, fraud string,
	signatureOverride string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("method = %s, mau GET", r.Method)
		}
		wantPath := "/v2/" + orderID + "/status"
		if r.URL.Path != wantPath {
			t.Errorf("path = %q, mau %q", r.URL.Path, wantPath)
		}
		// Auth Basic: base64(serverKey + ":") — tanpa password.
		if got := r.Header.Get("Authorization"); !strings.HasPrefix(got, "Basic ") {
			t.Errorf("Authorization = %q, mau Basic", got)
		}
		signature := signatureOverride
		if signature == "" {
			signature = MidtransSignature(orderID, statusCode, gross, statusTestKey)
		}
		body, err := json.Marshal(map[string]string{
			"order_id":           orderID,
			"status_code":        statusCode,
			"gross_amount":       gross,
			"transaction_status": txStatus,
			"fraud_status":       fraud,
			"transaction_id":     "txn-" + orderID,
			"signature_key":      signature,
		})
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(body)
	}))
}

func TestFetchStatusSettlementWithValidSignature(t *testing.T) {
	srv := newStatusServer(t, "TXN-1", "200", "102000.00", "settlement", "accept", "")
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), "TXN-1")
	if err != nil {
		t.Fatalf("FetchStatus error: %v", err)
	}
	if got.Status != "settlement" {
		t.Errorf("status = %q, mau \"settlement\"", got.Status)
	}
	if got.FraudStatus != "accept" {
		t.Errorf("fraud = %q, mau \"accept\"", got.FraudStatus)
	}
	if got.TransactionID != "txn-TXN-1" {
		t.Errorf("transaction_id = %q, mau %q", got.TransactionID, "txn-TXN-1")
	}
	if got.GrossAmount != "102000.00" {
		t.Errorf("gross_amount = %q, mau \"102000.00\"", got.GrossAmount)
	}
}

// Authenticated GET is the verification mechanism recommended by Midtrans.
// A capture response need not carry a matching webhook signature.
func TestFetchStatusAuthenticatedCaptureWithoutWebhookSignature(t *testing.T) {
	for _, signature := range []string{"", strings.Repeat("a", 128)} {
		t.Run(fmt.Sprintf("signature_present_%t", signature != ""), func(t *testing.T) {
			srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				key, password, ok := r.BasicAuth()
				if r.Method != http.MethodGet || r.URL.Path != "/v2/TXN-CAPTURE/status" || !ok || key != statusTestKey || password != "" {
					t.Error("status request must authenticate the requested order with server key")
					w.WriteHeader(http.StatusUnauthorized)
					return
				}
				body := map[string]string{
					"order_id": "TXN-CAPTURE", "status_code": "200", "status_message": "Success, transaction found",
					"gross_amount": "102000.00", "transaction_status": "capture", "fraud_status": "accept",
					"transaction_id": "capture-transaction", "payment_type": "credit_card", "currency": "IDR",
				}
				if signature != "" {
					body["signature_key"] = signature
				}
				_ = json.NewEncoder(w).Encode(body)
			}))
			defer srv.Close()
			g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})
			g.http = srv.Client()
			got, err := g.FetchStatus(t.Context(), "TXN-CAPTURE")
			if err != nil || got.Status != "capture" || got.FraudStatus != "accept" || got.GrossAmount != "102000.00" || got.TransactionID != "capture-transaction" {
				t.Fatalf("authenticated capture rejected: status=%+v err=%v", got, err)
			}
		})
	}
}

func TestFetchStatusRejectsWrongOrderID(t *testing.T) {
	for _, returnedOrder := range []string{"TXN-OTHER", ""} {
		t.Run(fmt.Sprintf("returned_order_%q", returnedOrder), func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_ = json.NewEncoder(w).Encode(map[string]string{
					"order_id": returnedOrder, "status_code": "200", "gross_amount": "102000.00",
					"transaction_status": "capture", "fraud_status": "accept",
					"signature_key": MidtransSignature("TXN-REQUESTED", "200", "102000.00", statusTestKey),
				})
			}))
			defer srv.Close()
			g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})
			if _, err := g.FetchStatus(t.Context(), "TXN-REQUESTED"); err == nil {
				t.Fatal("response for a different or missing order must not be accepted")
			}
		})
	}
}

func TestFetchStatusCodeTransactionPairs(t *testing.T) {
	for _, code := range []string{"200", "201", "202", "407", "401", "500", ""} {
		for _, status := range []string{"settlement", "capture", "pending", "expire", "cancel", "deny", "unknown", ""} {
			t.Run(code+"/"+status, func(t *testing.T) {
				provider := newStatusServer(t, "TXN-PAIR", code, "102000.00", status, "accept", "unused")
				defer provider.Close()
				gateway := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: provider.URL})
				got, err := gateway.FetchStatus(t.Context(), "TXN-PAIR")
				if err != nil {
					t.Fatal(err)
				}
				accepted := code == "200" || code == "201" && status == "pending" ||
					code == "202" && status == "deny" || code == "407" && status == "expire"
				want := "pending"
				if accepted && status != "unknown" && status != "" {
					want = status
				}
				if got.Status != want || got.StatusCode != code {
					t.Fatalf("status=%q code=%q, want status=%q code=%q", got.Status, got.StatusCode, want, code)
				}
				if accepted && (got.TransactionID != "txn-TXN-PAIR" || got.GrossAmount != "102000.00") {
					t.Fatalf("recognized transaction metadata lost: %+v", got)
				}
				if !accepted && (got.TransactionID != "" || got.GrossAmount != "") {
					t.Fatalf("unrecognized code/status exposed transaction metadata: %+v", got)
				}
			})
		}
	}
}

func TestFetchStatusRecognizedNon200RequiresMatchingOrder(t *testing.T) {
	for _, pair := range []struct{ code, status string }{{"201", "pending"}, {"202", "deny"}, {"407", "expire"}} {
		for _, returnedOrder := range []string{"TXN-OTHER", ""} {
			t.Run(pair.code+"/"+returnedOrder, func(t *testing.T) {
				provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					_ = json.NewEncoder(w).Encode(map[string]string{
						"order_id": returnedOrder, "status_code": pair.code, "transaction_status": pair.status,
					})
				}))
				defer provider.Close()
				gateway := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: provider.URL})
				if _, err := gateway.FetchStatus(t.Context(), "TXN-REQUESTED"); err == nil {
					t.Fatal("recognized transaction with wrong or missing order must be rejected")
				}
			})
		}
	}
}

// TestFetchStatusNotFoundMeansPending: transaksi yang belum ada di Midtrans
// bukan kegagalan — diperlakukan sebagai pending.
func TestFetchStatusNotFoundMeansPending(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"status_code":"404","status_message":"Transaction doesn't exist."}`))
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), "TXN-3")
	if err != nil {
		t.Fatalf("404 tidak boleh jadi error: %v", err)
	}
	if got.Status != "pending" {
		t.Errorf("status = %q, mau \"pending\"", got.Status)
	}
}

// TestFetchStatusNotFoundInBodyMeansPending mengunci perilaku ASLI Midtrans
// yang diuji langsung ke sandbox: transaksi yang belum ada dibalas
// **HTTP 200** dengan "status_code":"404" DI DALAM body, bukan HTTP 404.
//
// Respons itu tidak memuat signature_key maupun gross_amount. Tanpa cabang
// khusus, pemeriksaan signature selalu gagal sehingga endpoint polling
// mencatat error tiap 3 detik padahal keadaannya normal (token Snap baru
// dibuat dan belum dibayar).
func TestFetchStatusNotFoundInBodyMeansPending(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK) // Midtrans membalas 200, bukan 404
		_, _ = w.Write([]byte(`{"status_code":"404","status_message":"Transaction doesn't exist.","id":"abc"}`))
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), "TXN-BELUM-ADA")
	if err != nil {
		t.Fatalf("status_code 404 di body tidak boleh jadi error: %v", err)
	}
	if got.Status != "pending" {
		t.Errorf("status = %q, mau \"pending\"", got.Status)
	}
}

// TestFetchStatusNotExistWithoutStatusCode: sebagian respons hanya membawa
// `status_message` "Transaction doesn't exist" tanpa `status_code` — tetap
// pending tanpa error (jangan bergantung pada satu field saja).
func TestFetchStatusNotExistWithoutStatusCode(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status_message":"Transaction doesn't exist."}`))
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), "TXN-MSG")
	if err != nil {
		t.Fatalf("status_message \"doesn't exist\" tidak boleh jadi error: %v", err)
	}
	if got.Status != "pending" {
		t.Errorf("status = %q, mau \"pending\"", got.Status)
	}
}

// TestFetchStatusUnknownStatusCodeIsPending: kode status di luar 200/404 yang
// tidak kita kenal (dan tanpa signature) tidak boleh menggagalkan polling.
func TestFetchStatusUnknownStatusCodeIsPending(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status_code":"202","status_message":"Accepted"}`))
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), "TXN-202")
	if err != nil {
		t.Fatalf("status_code tak dikenal tidak boleh jadi error: %v", err)
	}
	if got.Status != "pending" {
		t.Errorf("status = %q, mau \"pending\"", got.Status)
	}
}

// TestFetchStatusUnknownTransactionStatusIsPending: respons transaksi nyata
// (signature valid) dengan `transaction_status` tak dikenal -> pending, bukan
// string mentah yang membingungkan handler.
func TestFetchStatusUnknownTransactionStatusIsPending(t *testing.T) {
	const orderID = "TXN-ANEh"
	const gross = "102000.00"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := json.Marshal(map[string]string{
			"order_id":           orderID,
			"status_code":        "200",
			"gross_amount":       gross,
			"transaction_status": "sesuatu-yang-baru",
			"signature_key":      MidtransSignature(orderID, "200", gross, statusTestKey),
		})
		_, _ = w.Write(body)
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	got, err := g.FetchStatus(t.Context(), orderID)
	if err != nil {
		t.Fatalf("status transaksi tak dikenal tidak boleh jadi error: %v", err)
	}
	if got.Status != "pending" {
		t.Errorf("status = %q, mau \"pending\"", got.Status)
	}
}

// TestFetchStatusServerError: kegagalan gateway dilaporkan sebagai error agar
// pemanggil memakai status DB.
func TestFetchStatusServerError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"status_message":"boom"}`))
	}))
	defer srv.Close()
	g := NewMidtransGateway(MidtransConfig{ServerKey: statusTestKey, APIBase: srv.URL})

	if _, err := g.FetchStatus(t.Context(), "TXN-4"); err == nil {
		t.Fatal("HTTP 500 harus menghasilkan error")
	}
}

// TestFetchStatusWithoutServerKey: tanpa kredensial, jangan menembak network.
func TestFetchStatusWithoutServerKey(t *testing.T) {
	g := NewMidtransGateway(MidtransConfig{APIBase: "http://127.0.0.1:1"})
	if _, err := g.FetchStatus(t.Context(), "TXN-5"); err == nil {
		t.Fatal("server key kosong harus menghasilkan error")
	}
}

// TestAPIBaseDefaultsFromEnv: host API status dipilih dari Env, dan tidak
// menimpa SnapBase yang sudah dipakai.
func TestAPIBaseDefaultsFromEnv(t *testing.T) {
	sandbox := NewMidtransGateway(MidtransConfig{ServerKey: "k", Env: "sandbox"})
	if sandbox.APIBase() != APIBaseSandbox {
		t.Errorf("apiBase sandbox = %q, mau %q", sandbox.APIBase(), APIBaseSandbox)
	}
	if sandbox.SnapBase() != SnapBaseSandbox {
		t.Errorf("snapBase sandbox = %q, mau %q", sandbox.SnapBase(), SnapBaseSandbox)
	}
	prod := NewMidtransGateway(MidtransConfig{ServerKey: "k", Env: "production"})
	if prod.APIBase() != APIBaseProduction {
		t.Errorf("apiBase production = %q, mau %q", prod.APIBase(), APIBaseProduction)
	}
	if prod.SnapBase() != SnapBaseProduction {
		t.Errorf("snapBase production = %q, mau %q", prod.SnapBase(), SnapBaseProduction)
	}
}
