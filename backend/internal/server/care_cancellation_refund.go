package server

import (
	"context"
	"errors"
	"time"

	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

type careRefundGateway interface {
	RefundPayment(context.Context, string, string, int64) (string, error)
}

func (s *Server) RunCareCancellationRefunds(ctx context.Context) error {
	gateway, ok := s.payment.(careRefundGateway)
	if !ok {
		return nil
	}
	ids, err := s.store.PendingCareCancellationRefunds(ctx)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		refundCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
		err := s.store.ProcessCareCancellationRefund(refundCtx, id, func(ctx context.Context, order, key string, amount int64) (string, error) {
			providerCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			defer cancel()
			external, err := gateway.RefundPayment(providerCtx, order, key, amount)
			if errors.Is(err, payment.ErrManualRefundRequired) {
				s.logger.Warn("refund sesi memerlukan penanganan manual", "refund_id", id)
				return "", store.ErrCareCancellationRefundManual
			}
			return external, err
		})
		cancel()
		if err != nil {
			s.logger.Warn("pengiriman refund sesi akan dicoba kembali", "refund_id", id, "error", err)
		}
	}
	return nil
}
