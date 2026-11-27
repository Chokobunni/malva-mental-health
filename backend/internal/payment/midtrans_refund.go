package payment

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
)

var ErrManualRefundRequired = errors.New("pengembalian dana memerlukan penanganan manual")

type midtransRefund struct {
	ID     json.Number `json:"refund_chargeback_id"`
	Key    string      `json:"refund_key"`
	Amount string      `json:"refund_amount"`
}

type midtransRefundResponse struct {
	midtransRefund
	OrderID string           `json:"order_id"`
	Code    string           `json:"status_code"`
	Status  string           `json:"transaction_status"`
	Method  string           `json:"payment_type"`
	Refunds []midtransRefund `json:"refunds"`
}

// RefundPayment uses a stable merchant key to reconcile indeterminate attempts.
func (g *MidtransGateway) RefundPayment(ctx context.Context, orderID, key string, amount int64) (string, error) {
	if g.serverKey == "" || orderID == "" || key == "" || amount <= 0 {
		return "", errors.New("data refund Midtrans tidak valid")
	}
	payload, err := json.Marshal(map[string]any{"refund_key": key, "amount": amount, "reason": "Pembatalan sesi Malva"})
	if err != nil {
		return "", err
	}
	endpoint := g.apiBase + "/v2/" + url.PathEscape(orderID)
	out, err := g.requestRefund(ctx, http.MethodPost, endpoint+"/refund", payload)
	if err != nil {
		return "", err
	}
	if out.Code == "200" && out.OrderID == orderID && out.Status == "refund" && out.matches(key, amount) {
		return out.ID.String(), nil
	}
	switch out.Code {
	case "406", "412", "414":
		status, checkErr := g.requestRefund(ctx, http.MethodGet, endpoint+"/status", nil)
		if checkErr != nil {
			return "", checkErr
		}
		if status.Code == "200" && status.OrderID == orderID {
			if status.Status == "refund" {
				for _, refund := range status.Refunds {
					if refund.matches(key, amount) {
						return refund.ID.String(), nil
					}
				}
			}
			if status.Status == "settlement" {
				if (out.Code == "412" && status.Method != "" && !supportsMidtransRefund(status.Method)) || out.Code == "414" {
					return "", ErrManualRefundRequired
				}
			}
		}
	}
	return "", fmt.Errorf("Midtrans belum menyetujui refund (kode %q)", out.Code)
}

func (g *MidtransGateway) requestRefund(ctx context.Context, method, endpoint string, payload []byte) (midtransRefundResponse, error) {
	var out midtransRefundResponse
	req, err := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(payload))
	if err != nil {
		return out, err
	}
	req.SetBasicAuth(g.serverKey, "")
	req.Header.Set("Accept", "application/json")
	if len(payload) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := g.http.Do(req)
	if err != nil {
		return out, errors.New("gagal menghubungi Midtrans untuk refund")
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode >= 500 {
		return out, fmt.Errorf("HTTP refund Midtrans %d", resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&out); err != nil {
		return out, errors.New("respons refund Midtrans tidak valid")
	}
	return out, nil
}

func (r midtransRefund) matches(key string, amount int64) bool {
	value, ok := new(big.Rat).SetString(r.Amount)
	return ok && r.Key == key && r.ID.String() != "" && value.Cmp(big.NewRat(amount, 1)) == 0
}

func supportsMidtransRefund(method string) bool {
	switch method {
	case "credit_card", "gopay", "shopeepay", "dana", "ovo", "qris", "kredivo", "akulaku":
		return true
	}
	return false
}
