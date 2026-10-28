package notify

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"

	"malva/backend/internal/config"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// errNoProjectID dikembalikan bila kredensial FCM ada tetapi project ID
// tidak dapat ditentukan — meminta operator menetapkan MALVA_FCM_PROJECT_ID
// secara eksplisit lebih aman daripada memakai default yang menebak.
var errNoProjectID = errors.New("FCM project ID tidak ditemukan; isi MALVA_FCM_PROJECT_ID atau pastikan kredensial memuat project_id")

type Message struct {
	Token string
	Title string
	Body  string
	Data  map[string]string
}

type Provider interface {
	Send(ctx context.Context, message Message) error
}

type noopProvider struct {
	logger *slog.Logger
}

func NewProvider(ctx context.Context, cfg config.Config, logger *slog.Logger) (Provider, error) {
	if cfg.FCMCredentialsFile == "" && cfg.FCMCredentialsJSON == "" {
		logger.Warn("FCM credentials are not configured; using no-op notification provider")
		return noopProvider{logger: logger}, nil
	}

	// Project ID wajib agar Messaging client dapat dibuat. Diambil dari
	// MALVA_FCM_PROJECT_ID bila diisi, atau otomatis dari `project_id`
	// pada kredensial service account (backend selalu sinkron dengan
	// project Firebase tanpa env manual).
	projectID := cfg.FCMProjectID
	if projectID == "" {
		projectID = detectProjectID(cfg)
	}
	if projectID == "" {
		return nil, errNoProjectID
	}

	var opts []option.ClientOption
	if cfg.FCMCredentialsJSON != "" {
		opts = append(opts, option.WithAuthCredentialsJSON(option.ServiceAccount, []byte(cfg.FCMCredentialsJSON)))
	} else {
		opts = append(opts, option.WithAuthCredentialsFile(option.ServiceAccount, cfg.FCMCredentialsFile))
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID}, opts...)
	if err != nil {
		return nil, err
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, err
	}
	logger.Info("fcm provider active", "project_id", projectID)
	return &fcmProvider{client: client, projectID: projectID}, nil
}

// detectProjectID membaca `project_id` dari kredensial service account
// (file atau JSON inline). Mengembalikan "" bila tidak dapat dibaca —
func detectProjectID(cfg config.Config) string {
	// []byte("") bukan nil, jadi uji panjang — bukan nil.
	raw := []byte(cfg.FCMCredentialsJSON)
	if len(raw) == 0 && cfg.FCMCredentialsFile != "" {
		b, err := os.ReadFile(cfg.FCMCredentialsFile)
		if err != nil {
			return ""
		}
		raw = b
	}
	if len(raw) == 0 {
		return ""
	}
	var creds struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(raw, &creds); err != nil {
		return ""
	}
	return creds.ProjectID
}

func (p noopProvider) Send(ctx context.Context, message Message) error {
	p.logger.Info("notification skipped by no-op provider", "token", redactToken(message.Token), "title", message.Title)
	return nil
}

type fcmProvider struct {
	client    *messaging.Client
	projectID string
}

func (p *fcmProvider) Send(ctx context.Context, message Message) error {
	_, err := p.client.Send(ctx, &messaging.Message{
		Token: message.Token,
		Notification: &messaging.Notification{
			Title: message.Title,
			Body:  message.Body,
		},
		Data: message.Data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				ChannelID: "malva_updates",
			},
		},
	})
	return err
}

func redactToken(token string) string {
	if len(token) <= 8 {
		return "***"
	}
	return token[:4] + "..." + token[len(token)-4:]
}
