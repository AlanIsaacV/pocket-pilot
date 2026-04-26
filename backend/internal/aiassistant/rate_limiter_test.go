package aiassistant_test

import (
	"context"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
	"github.com/AlanIsaacV/pocket-pilot/internal/testdb"
)

// TestRateLimiter_FeaturesIsolated verifica que dos RateLimiters compartiendo
// el mismo Repository pero con `feature` distinto cuentan cuotas
// independientes. Crítico para Fase 4: agotar cuota de chat NO debe agotar la
// de notification_parser y viceversa.
func TestRateLimiter_FeaturesIsolated(t *testing.T) {
	pool := testdb.OpenPool(t)
	ctx := context.Background()
	user := testdb.NewUser(t, pool)

	repo := aiassistant.NewRepository(pool)
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM ai_usage WHERE user_id = $1`, user)
	})

	// Límites bajos para llegar a saturación rápido.
	chatLimiter := aiassistant.NewRateLimiter(repo, aiassistant.FeatureChat, 2, 1_000_000)
	notiLimiter := aiassistant.NewRateLimiter(repo, aiassistant.FeatureNotificationParser, 2, 1_000_000)

	// 2 requests al chat — saturan el limiter de chat pero no el otro.
	for i := 0; i < 2; i++ {
		if err := repo.RecordUsage(ctx, user, aiassistant.FeatureChat, "gemini-3.1-flash-lite-preview", 100, 100); err != nil {
			t.Fatalf("record chat usage: %v", err)
		}
	}

	// chat limit alcanzado → debe rechazar.
	err := chatLimiter.Check(ctx, user)
	if err == nil {
		t.Fatal("expected chat limiter to reject, got nil")
	}
	if s, _ := status.FromError(err); s.Code() != codes.ResourceExhausted {
		t.Fatalf("expected ResourceExhausted, got %v", s.Code())
	}

	// notification_parser NO afectado: cuota intacta.
	if err := notiLimiter.Check(ctx, user); err != nil {
		t.Fatalf("noti limiter should not be exhausted: %v", err)
	}

	// Cargar al limit de notification_parser y verificar que el de chat sigue
	// rechazando (sin cambio) y el de noti rechaza también.
	for i := 0; i < 2; i++ {
		if err := repo.RecordUsage(ctx, user, aiassistant.FeatureNotificationParser, "gemini-3.1-flash-lite-preview", 50, 50); err != nil {
			t.Fatalf("record noti usage: %v", err)
		}
	}
	if err := notiLimiter.Check(ctx, user); err == nil {
		t.Fatal("expected noti limiter to reject, got nil")
	}
	if err := chatLimiter.Check(ctx, user); err == nil {
		t.Fatal("expected chat limiter to still reject, got nil")
	}
}
