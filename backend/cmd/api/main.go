package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/logging"
	"malva/backend/internal/notify"
	"malva/backend/internal/realtime"
	"malva/backend/internal/server"
	"malva/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	// Logger terpusat dibuat SETELAH config.Load agar level (MALVA_LOG_LEVEL)
	// sudah terbaca. logging.SetDefault memasangnya sebagai logger default,
	// sehingga pemanggilan slog.* yang tersebar di server/store ikut memakai
	// logger JSON terpusat ini (bukan handler teks default ke stderr).
	logger := logging.New(cfg.LogLevel, os.Stdout)
	logging.SetDefault(logger)

	// Koneksi DB terpusat: timestamptz di-decode dalam zona WIB (lihat store.OpenSQL).
	db, err := store.OpenSQL(cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer func() { _ = db.Close() }()
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pingCtx, cancelPing := context.WithTimeout(ctx, 5*time.Second)
	defer cancelPing()
	if err := db.PingContext(pingCtx); err != nil {
		return err
	}

	st := store.New(db)
	authManager := auth.NewManager(cfg.JWTSecret)
	hub := realtime.NewHub(logger, cfg.OriginAllowed, st)
	provider, err := notify.NewProvider(ctx, cfg, logger)
	if err != nil {
		return err
	}
	worker := notify.NewOutboxWorker(st, provider, hub, logger)
	go worker.Run(ctx)

	app := server.New(cfg, authManager, st, hub, logger)

	// Backfill sekali saat start: sesi video terjadwal yang belum punya link
	// Google Meet (termasuk yang masih memakai link penyedia lama) dibuatkan
	// sekarang, agar pasien tidak menemukan sesi tanpa ruang pertemuan.
	go func() {
		bctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		if n, err := app.BackfillMissingMeetLinks(bctx, 25); err != nil {
			logger.Warn("backfill link Meet gagal", "error", err)
		} else if n > 0 {
			logger.Info("backfill link Meet selesai", "created", n)
		}
	}()

	// Sweeper paket/sesi: kedaluwarsakan paket 6 minggu, hanguskan
	// pending_payment, auto-complete sesi lama, dan kirim pengingat sesi
	// video yang akan dimulai. Tiap 10 menit.
	go func() {
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		sweep := func() {
			sctx, cancel := context.WithTimeout(context.Background(), time.Minute)
			defer cancel()
			exp, expS, done, err := st.SweepCareState(sctx)
			if err != nil {
				logger.Warn("care sweep failed", "error", err)
			} else if exp+expS+done > 0 {
				logger.Info("care sweep", "expired_packages", exp, "expired_sessions", expS, "completed_sessions", done)
			}
			// Pengingat sesi video: jendela 15-25 menit sebelum mulai, lebih
			// lebar dari interval ticker agar tidak ada sesi yang terlewat.
			if sent, rerr := app.RunSessionReminders(sctx); rerr != nil {
				logger.Warn("session reminder failed", "error", rerr)
			} else if sent > 0 {
				logger.Info("session reminders sent", "count", sent)
			}
		}
		sweep()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				sweep()
			}
		}
	}()

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           app.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("malva api listening", "addr", cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
			return
		}
		errCh <- nil
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancelShutdown()
		return httpServer.Shutdown(shutdownCtx)
	case err := <-errCh:
		return err
	}
}
