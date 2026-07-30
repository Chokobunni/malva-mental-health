package notify

import (
	"context"
	"errors"
	"log/slog"
	"time"

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

	var sendErr error
	for _, token := range tokens {
		message := Message{
			Token: token,
			Title: job.Title,
			Body:  job.Body,
			Data:  job.Data,
		}
		if err := w.provider.Send(ctx, message); err != nil {
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
