package notify

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// FonnteSender mengirim WhatsApp sungguhan lewat gateway Fonnte
// (https://docs.fonnte.com/api-send-message). Ini satu-satunya kanal keluar
// yang benar-benar sampai ke kontak darurat saat SOS; sebelum ada sender ini
// blast hanya ditulis ke log audit lalu ditandai "sent".
type FonnteSender struct {
	token   string
	baseURL string
	client  *http.Client
}

// NewFonnteSender mengembalikan nil bila token kosong. Pemanggil cukup
// memeriksa nil untuk tahu kanal keluar belum dikonfigurasi — dengan begitu
// SOS tidak pernah mengklaim pesan terkirim tanpa transport nyata.
func NewFonnteSender(token, baseURL string) *FonnteSender {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil
	}
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {
		baseURL = "https://api.fonnte.com"
	}
	return &FonnteSender{
		token:   token,
		baseURL: baseURL,
		client:  &http.Client{Timeout: 15 * time.Second},
	}
}

// fonnteResponse mengikuti respons resmi: sukses memakai "status": true beserta
// "id" (array) dan "process"; gagal memakai "status": false + "reason"
// (mis. "token invalid", "target invalid", "insufficient quota").
type fonnteResponse struct {
	Status    bool     `json:"status"`
	Reason    string   `json:"reason"`
	Detail    string   `json:"detail"`
	ID        []string `json:"id"`
	Process   string   `json:"process"`
	RequestID int64    `json:"requestid"`
}

// Send mengirim satu pesan WhatsApp dan mengembalikan ID pesan dari gateway
// bila benar-benar diterima. Error berisi alasan penolakan gateway apa adanya
// agar bisa dicatat pada sos_blast_log.
func (f *FonnteSender) Send(ctx context.Context, phone, message string) (string, error) {
	if f == nil {
		return "", errors.New("kanal WhatsApp belum dikonfigurasi")
	}
	target := normalisasiNomorWA(phone)
	if target == "" {
		return "", errors.New("nomor kontak tidak valid")
	}

	form := url.Values{}
	form.Set("target", target)
	form.Set("message", message)
	form.Set("countryCode", "62")

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		f.baseURL+"/send", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	// Fonnte memakai token apa adanya pada header Authorization (tanpa Bearer).
	req.Header.Set("Authorization", f.token)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	res, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = res.Body.Close() }()

	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<16))
	if err != nil {
		return "", err
	}
	var out fonnteResponse
	if jerr := json.Unmarshal(body, &out); jerr != nil {
		return "", fmt.Errorf("respons gateway tidak terbaca (HTTP %d)", res.StatusCode)
	}
	if !out.Status {
		reason := strings.TrimSpace(out.Reason)
		if reason == "" {
			reason = fmt.Sprintf("gateway menolak (HTTP %d)", res.StatusCode)
		}
		return "", errors.New(reason)
	}
	if len(out.ID) > 0 {
		return out.ID[0], nil
	}
	return "", nil
}

// normalisasiNomorWA membuang spasi/tanda baca lalu menyesuaikan ke format
// internasional (62…) yang diharapkan Fonnte. Nomor kosong/terlalu pendek
// menghasilkan string kosong agar pemanggil bisa menandainya gagal.
func normalisasiNomorWA(phone string) string {
	var b strings.Builder
	for _, r := range phone {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	n := b.String()
	switch {
	case strings.HasPrefix(n, "0"):
		n = "62" + strings.TrimPrefix(n, "0")
	case strings.HasPrefix(n, "8"):
		n = "62" + n
	}
	if len(n) < 10 {
		return ""
	}
	return n
}
