package notify

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"time"

	firebase_messaging "firebase.google.com/go/v4/messaging"

	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

type OutboxWorker struct {
	store    *store.Store
	provider Provider
	hub      *realtime.Hub
	logger   *slog.Logger
}

func NewOutboxWorker(st *store.Store, provider Provider, hub *realtime.Hub, logger *slog.Logger) *OutboxWorker {
	return &OutboxWorker{
		store:    st,
		provider: provider,
		hub:      hub,
		logger:   logger,
	}
}

func (w *OutboxWorker) Run(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		w.process(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (w *OutboxWorker) process(ctx context.Context) {
	jobs, err := w.store.AcquireOutboxJobs(ctx, 20)
	if err != nil {
		w.logger.Warn("notification outbox acquire failed", "error", err)
		return
	}
	for _, job := range jobs {
		if err := w.sendJob(ctx, job); err != nil {
			w.logger.Warn("notification outbox send failed", "job_id", job.ID, "error", err)
		}
	}
}

func (w *OutboxWorker) sendJob(ctx context.Context, job store.OutboxJob) error {
	tokens, err := w.store.EnabledDeviceTokens(ctx, job.UserID)
	if err != nil {
		w.markFailed(ctx, job, err)
		return err
	}
	if len(tokens) == 0 {
		if err := w.store.MarkOutboxDelivered(ctx, job.ID); err != nil {
			return err
		}
		w.hub.Publish(job.UserID, realtime.Event{
			Type: "notification.no_device_token",
			Data: map[string]string{"notification_id": job.NotificationID},
		})
		return nil
	}

	collapseKey := collapseKeyFor(job.Data)
	var sendErr error
	for _, token := range tokens {
		message := Message{
			Token:       token,
			Title:       job.Title,
			Body:        job.Body,
			Data:        job.Data,
			CollapseKey: collapseKey,
		}
		if err := w.provider.Send(ctx, message); err != nil {
			// Token tak terdaftar/tidak valid (mis. uninstall/reinstall):
			// nonaktifkan token itu lalu lanjut ke token lain — jangan
			// gagalkan seluruh job karena satu token basi.
			if isDeadTokenError(err) {
				if derr := w.store.DisableDeviceToken(ctx, token); derr != nil {
					w.logger.Warn("notification outbox disable dead token failed", "job_id", job.ID, "error", derr)
				} else {
					w.logger.Info("notification outbox disabled dead token", "job_id", job.ID, "token", redactToken(token))
				}
				continue
			}
			sendErr = errors.Join(sendErr, err)
		}
	}
	if sendErr != nil {
		w.markFailed(ctx, job, sendErr)
		return sendErr
	}
	if err := w.store.MarkOutboxDelivered(ctx, job.ID); err != nil {
		return err
	}
	w.hub.Publish(job.UserID, realtime.Event{
		Type: "notification.sent",
		Data: map[string]string{"notification_id": job.NotificationID},
	})
	return nil
}

// collapseKeyFor menyusun kunci kolaps notifikasi dari jenis peristiwa dan
// (bila ada) ID sesi. Peristiwa yang sama pada sesi yang sama memakai kunci
// yang sama sehingga menimpa notifikasi sebelumnya, bukan menumpuk. Tanpa
// session_id, cukup pakai kind.
func collapseKeyFor(data map[string]string) string {
	kind := strings.TrimSpace(data["kind"])
	sessionID := strings.TrimSpace(data["session_id"])
	if kind == "" {
		return ""
	}
	if sessionID == "" {
		return kind
	}
	return kind + ":" + sessionID
}

// isDeadTokenError melaporkan apakah galat FCM menandakan token yang sudah
// tidak terdaftar/tidak valid (perangkat uninstall, token diputar). Deteksi
// utama memakai helper SDK; fallback ke pencocokan teks galat bila tipe galat
// SDK berubah antarversi.
func isDeadTokenError(err error) bool {
	if err == nil {
		return false
	}
	if firebase_messaging.IsUnregistered(err) || firebase_messaging.IsInvalidArgument(err) {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "registration-token-not-registered") ||
		strings.Contains(msg, "invalid-argument") ||
		strings.Contains(msg, "not-registered")
}

func (w *OutboxWorker) markFailed(ctx context.Context, job store.OutboxJob, err error) {
	terminal := job.Attempts >= 5
	delay := time.Duration(job.Attempts*job.Attempts) * 30 * time.Second
	if delay > 15*time.Minute {
		delay = 15 * time.Minute
	}
	if markErr := w.store.MarkOutboxFailed(ctx, job.ID, err.Error(), time.Now().Add(delay), terminal); markErr != nil {
		w.logger.Warn("notification outbox mark failed failed", "job_id", job.ID, "error", markErr)
	}
}
