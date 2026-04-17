package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
	"github.com/AlanIsaacV/pocket-pilot/internal/auth"
	"github.com/AlanIsaacV/pocket-pilot/internal/budget"
	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/config"
	"github.com/AlanIsaacV/pocket-pilot/internal/database"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/goal"
	"github.com/AlanIsaacV/pocket-pilot/internal/jwks"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/tag"
	"github.com/AlanIsaacV/pocket-pilot/internal/transaction"
	"github.com/AlanIsaacV/pocket-pilot/internal/transactiontemplate"
	"github.com/AlanIsaacV/pocket-pilot/internal/userpreference"
	"github.com/AlanIsaacV/pocket-pilot/internal/yieldconfig"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()

	pool, err := database.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()
	slog.Info("connected to PostgreSQL")

	// Shared sync cursor store used by every repository below.
	cursorStore := sync.NewCursorStore(pool)

	// Wire up repositories and handlers
	accountHandler := account.NewHandler(account.NewRepository(pool, cursorStore))
	categoryHandler := category.NewHandler(category.NewRepository(pool, cursorStore))
	transactionHandler := transaction.NewHandler(transaction.NewRepository(pool, cursorStore))
	transactionTemplateHandler := transactiontemplate.NewHandler(transactiontemplate.NewRepository(pool, cursorStore))
	yieldConfigHandler := yieldconfig.NewHandler(yieldconfig.NewRepository(pool, cursorStore))
	goalHandler := goal.NewHandler(goal.NewRepository(pool, cursorStore))
	budgetHandler := budget.NewHandler(budget.NewRepository(pool, cursorStore))
	tagHandler := tag.NewHandler(tag.NewRepository(pool, cursorStore))
	userPreferenceHandler := userpreference.NewHandler(userpreference.NewRepository(pool, cursorStore))

	// SyncService handler (preflight GetSyncStatus).
	syncHandler := sync.NewHandler(cursorStore)

	// AI Assistant
	geminiProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey)
	aiRepo := aiassistant.NewRepository(pool)
	aiRateLimiter := aiassistant.NewRateLimiter(aiRepo, cfg.AIDailyRequestLimit, cfg.AIMonthlyTokenLimit)
	aiHandler := aiassistant.NewHandler(geminiProvider, aiRateLimiter, aiRepo)

	// Auth
	keyStore := jwks.NewKeyStore()
	verifier := jwks.NewVerifier(keyStore, cfg.GoogleClientID, cfg.AppleClientID)
	tokenService := auth.NewTokenService(cfg.JWTSecret)
	authRepo := auth.NewRepository(pool)
	authHandler := auth.NewHandler(authRepo, verifier, tokenService)

	// gRPC server with chained interceptors: auth first, then logging.
	srv := grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			middleware.NewUnaryAuthInterceptor(cfg.JWTSecret),
			middleware.NewUnaryLoggingInterceptor(),
		),
	)
	pb.RegisterAccountServiceServer(srv, accountHandler)
	pb.RegisterCategoryServiceServer(srv, categoryHandler)
	pb.RegisterTransactionServiceServer(srv, transactionHandler)
	pb.RegisterTransactionTemplateServiceServer(srv, transactionTemplateHandler)
	pb.RegisterYieldConfigServiceServer(srv, yieldConfigHandler)
	pb.RegisterGoalServiceServer(srv, goalHandler)
	pb.RegisterBudgetServiceServer(srv, budgetHandler)
	pb.RegisterTagServiceServer(srv, tagHandler)
	pb.RegisterUserPreferenceServiceServer(srv, userPreferenceHandler)
	pb.RegisterAIAssistantServiceServer(srv, aiHandler)
	pb.RegisterAuthServiceServer(srv, authHandler)
	pb.RegisterSyncServiceServer(srv, syncHandler)

	reflection.Register(srv)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", cfg.GRPCPort))
	if err != nil {
		slog.Error("listen", "error", err)
		os.Exit(1)
	}

	// Graceful shutdown on CTRL+C or SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-quit
		slog.Info("shutting down...")
		srv.GracefulStop()
	}()

	slog.Info("gRPC server listening", "port", cfg.GRPCPort)
	if err := srv.Serve(lis); err != nil {
		slog.Error("serve", "error", err)
		os.Exit(1)
	}
}
