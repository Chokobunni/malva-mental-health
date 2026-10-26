// Package logging menyediakan logger terstruktur terpusat (di atas
// log/slog) untuk seluruh backend Malva. Tujuannya menstandarkan format
// log (JSON), level, dan field dasar seperti "service" agar log mudah
// dikonsumsi agregator log.
package logging

import (
	"io"
	"log/slog"
	"strings"
)

// New membuat logger slog dengan handler JSON ke w, pada level tertentu,
// dan menambahkan field tetap "service":"malva-api".
//
// Level yang dikenal: "debug", "info" (default), "warn"/"warning", "error".
// Nilai tak dikenal diperlakukan sebagai "info".
func New(level string, w io.Writer) *slog.Logger {
	var lv slog.Level
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "debug":
		lv = slog.LevelDebug
	case "warn", "warning":
		lv = slog.LevelWarn
	case "error":
		lv = slog.LevelError
	default:
		lv = slog.LevelInfo
	}
	handler := slog.NewJSONHandler(w, &slog.HandlerOptions{Level: lv})
	return slog.New(handler).With("service", "malva-api")
}

// SetDefault memasang l sebagai logger default paket log/slog, sehingga
// pemanggilan slog.Info/slog.Error di kode lain ikut memakai logger ini.
func SetDefault(l *slog.Logger) {
	slog.SetDefault(l)
}

// Err mengembalikan atribut terstruktur untuk sebuah error. Aman terhadap
// nilai nil (menghasilkan atribut dengan nilai nil, bukan panic).
func Err(err error) slog.Attr {
	return slog.Any("error", err)
}
