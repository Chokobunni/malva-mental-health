package main

import (
	"context"
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/notify"
	"malva/backend/internal/realtime"
	"malva/backend/internal/server"
	"malva/backend/internal/store"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if err := run(logger); err != nil {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
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
	hub := realtime.NewHub(logger, cfg.OriginAllowed)
	provider, err := notify.NewProvider(ctx, cfg, logger)
	if err != nil {
		return err
	}
	worker := notify.NewOutboxWorker(st, provider, hub, logger)
	go worker.Run(ctx)

	app := server.New(cfg, authManager, st, hub, logger)
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
