package payment

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMidtransSnapReturnsToMalvaWithReference(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Callbacks struct {
				Finish string `json:"finish"`
			} `json:"callbacks"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body.Callbacks.Finish != "malva://payment/return?reference=TXN-TEST" {
			t.Errorf("missing payment return callback: %q", body.Callbacks.Finish)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"token":"snap-test","redirect_url":"https://gateway.test/pay"}`))
	}))
	defer srv.Close()
	gw := NewMidtransGateway(MidtransConfig{ServerKey: "synthetic-key", SnapBase: srv.URL})
	if _, err := gw.CreateTransaction(context.Background(), "TXN-TEST", 102000, nil); err != nil {
		t.Fatal(err)
	}
}
