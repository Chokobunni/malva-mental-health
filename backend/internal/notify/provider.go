package notify

import (
	"context"
	"log/slog"

	"malva/backend/internal/config"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

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

	var opts []option.ClientOption
	if cfg.FCMCredentialsJSON != "" {
		opts = append(opts, option.WithCredentialsJSON([]byte(cfg.FCMCredentialsJSON)))
	} else {
		opts = append(opts, option.WithCredentialsFile(cfg.FCMCredentialsFile))
	}
	app, err := firebase.NewApp(ctx, nil, opts...)
	if err != nil {
		return nil, err
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, err
	}
	return &fcmProvider{client: client}, nil
}

func (p noopProvider) Send(ctx context.Context, message Message) error {
	p.logger.Info("notification skipped by no-op provider", "token", redactToken(message.Token), "title", message.Title)
	return nil
}

type fcmProvider struct {
	client *messaging.Client
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
