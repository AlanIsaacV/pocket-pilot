package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
	"github.com/AlanIsaacV/pocket-pilot/internal/auth"
	"github.com/AlanIsaacV/pocket-pilot/internal/bankalias"
	"github.com/AlanIsaacV/pocket-pilot/internal/bankpackage"
	"github.com/AlanIsaacV/pocket-pilot/internal/budget"
	"github.com/AlanIsaacV/pocket-pilot/internal/cardmapping"
	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/config"
	"github.com/AlanIsaacV/pocket-pilot/internal/database"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/goal"
	"github.com/AlanIsaacV/pocket-pilot/internal/investment"
	"github.com/AlanIsaacV/pocket-pilot/internal/jwks"
	"github.com/AlanIsaacV/pocket-pilot/internal/marketprice"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
	"github.com/AlanIsaacV/pocket-pilot/internal/notificationparser"
	"github.com/AlanIsaacV/pocket-pilot/internal/parserfeedback"
	"github.com/AlanIsaacV/pocket-pilot/internal/sync"
	"github.com/AlanIsaacV/pocket-pilot/internal/tag"
	"github.com/AlanIsaacV/pocket-pilot/internal/transaction"
	"github.com/AlanIsaacV/pocket-pilot/internal/transactiontemplate"
	"github.com/AlanIsaacV/pocket-pilot/internal/txrule"
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
	cardMappingHandler := cardmapping.NewHandler(cardmapping.NewRepository(pool, cursorStore))
	txRuleHandler := txrule.NewHandler(txrule.NewRepository(pool, cursorStore))
	notificationParserRepo := notificationparser.NewRepository(pool, cursorStore)
	parserFeedbackHandler := parserfeedback.NewHandler(parserfeedback.NewRepository(pool, cursorStore))

	// Fase 8: catálogo global de paquetes bancarios + sugerencias anónimas
	// + alias per-user. bank_packages mirror notification_parsers (global,
	// pull-only, bumpAllUsers); bank_aliases mirror cardmapping (user-scoped,
	// push+pull, LWW).
	bankPackageHandler := bankpackage.NewHandler(
		bankpackage.NewRepository(pool, cursorStore),
		bankpackage.NewSuggestionRepository(pool),
	)
	bankAliasHandler := bankalias.NewHandler(bankalias.NewRepository(pool, cursorStore))

	// Investments: renta variable (acciones, ETFs). Repositories extracted
	// to variables so the market price scheduler and admin handler share
	// them with the read-path handlers.
	holdingRepo := investment.NewHoldingRepository(pool, cursorStore)
	marketPriceRepo := investment.NewMarketPriceRepository(pool, cursorStore)
	holdingHandler := investment.NewHoldingHandler(holdingRepo)
	lotHandler := investment.NewLotHandler(investment.NewLotRepository(pool, cursorStore))
	splitHandler := investment.NewSplitHandler(investment.NewSplitRepository(pool, cursorStore))
	marketPriceHandler := investment.NewMarketPriceHandler(marketPriceRepo)

	// SyncService handler (preflight GetSyncStatus).
	syncHandler := sync.NewHandler(cursorStore)

	// AI Assistant. El chat y el notification_parser usan providers Gemini
	// independientes para que cada feature pueda configurar su propio modelo
	// (AI_CHAT_MODEL vs NOTIFICATION_PARSER_MODEL). Comparten el Repository
	// y la tabla ai_usage; el RateLimiter de cada feature filtra por la
	// columna `feature` y el modelo efectivo se persiste en `ai_usage.model`.
	chatProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey, cfg.AIChatModel)
	aiRepo := aiassistant.NewRepository(pool)
	aiRateLimiter := aiassistant.NewRateLimiter(aiRepo, aiassistant.FeatureChat, cfg.AIDailyRequestLimit, cfg.AIMonthlyTokenLimit)
	aiHandler := aiassistant.NewHandler(chatProvider, aiRateLimiter, aiRepo)

	// Notification parser LLM fallback (Fase 4). Provider Gemini propio con
	// modelo configurable; el rate limiter es independiente del chat.
	parserProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey, cfg.NotificationParserModel)
	notiParserLimiter := aiassistant.NewRateLimiter(
		aiRepo,
		aiassistant.FeatureNotificationParser,
		cfg.NotificationParserDailyLimit,
		cfg.NotificationParserMonthlyTokenLimit,
	)
	candidateRepo := notificationparser.NewCandidateRepository(pool)
	llmFallback := notificationparser.NewLLMFallback(
		parserProvider, notiParserLimiter, aiRepo, candidateRepo,
	)
	notificationParserHandler := notificationparser.NewHandlerWithLLM(notificationParserRepo, llmFallback)

	// Retention sweeper para candidate_parsers: anonimiza sample_* después
	// de 90 días. Corre una vez al startup y luego cada 24h. El ctx raíz
	// del proceso garantiza shutdown limpio.
	startCandidateRetentionSweeper(ctx, candidateRepo)

	// Auth
	keyStore := jwks.NewKeyStore()
	verifier := jwks.NewVerifier(keyStore, cfg.GoogleClientID, cfg.AppleClientID)
	tokenService := auth.NewTokenService(cfg.JWTSecret)
	authRepo := auth.NewRepository(pool)
	authHandler := auth.NewHandler(authRepo, verifier, tokenService)

	// Admin RPCs bypass JWT when the caller presents
	// MARKETPRICE_ADMIN_TOKEN (see middleware/auth.go).
	adminMethods := map[string]bool{
		pb.MarketPriceAdminService_AdminRefreshMarketPrices_FullMethodName: true,
	}

	// gRPC server with chained interceptors: auth first, then logging.
	srv := grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			middleware.NewUnaryAuthInterceptor(cfg.JWTSecret, cfg.MarketPriceAdminToken, adminMethods),
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
	pb.RegisterInvestmentHoldingServiceServer(srv, holdingHandler)
	pb.RegisterInvestmentLotServiceServer(srv, lotHandler)
	pb.RegisterInvestmentSplitServiceServer(srv, splitHandler)
	pb.RegisterMarketPriceServiceServer(srv, marketPriceHandler)
	pb.RegisterAIAssistantServiceServer(srv, aiHandler)
	pb.RegisterAuthServiceServer(srv, authHandler)
	pb.RegisterSyncServiceServer(srv, syncHandler)
	pb.RegisterAccountCardMappingServiceServer(srv, cardMappingHandler)
	pb.RegisterTransactionRuleServiceServer(srv, txRuleHandler)
	pb.RegisterNotificationParserServiceServer(srv, notificationParserHandler)
	pb.RegisterParserFeedbackServiceServer(srv, parserFeedbackHandler)
	pb.RegisterBankPackageServiceServer(srv, bankPackageHandler)
	pb.RegisterBankAliasServiceServer(srv, bankAliasHandler)

	// Market price cron — gated by MARKETPRICE_ENABLED so dev machines do
	// not hit Yahoo on boot unless explicitly asked.
	var priceScheduler *marketprice.Scheduler
	if cfg.MarketPriceEnabled {
		httpClient := &http.Client{Timeout: 5 * time.Second}
		var provider marketprice.MarketPriceProvider
		switch cfg.MarketPriceProvider {
		case "yahoo":
			provider = marketprice.NewYahooProvider(httpClient)
		default:
			slog.Error("marketprice: unknown provider", "provider", cfg.MarketPriceProvider)
			os.Exit(1)
		}
		priceScheduler = marketprice.NewScheduler(provider, marketPriceRepo, holdingRepo, cfg.MarketPriceRunOnBoot)
		priceScheduler.Start(ctx)

		adminHandler := marketprice.NewAdminHandler(priceScheduler, holdingRepo)
		pb.RegisterMarketPriceAdminServiceServer(srv, adminHandler)
		slog.Info("marketprice: scheduler registered",
			"provider", provider.Name(),
			"run_on_boot", cfg.MarketPriceRunOnBoot,
			"admin_rpc", cfg.MarketPriceAdminToken != "",
		)
	}

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
		if priceScheduler != nil {
			priceScheduler.Stop()
		}
		srv.GracefulStop()
	}()

	slog.Info("gRPC server listening", "port", cfg.GRPCPort)
	if err := srv.Serve(lis); err != nil {
		slog.Error("serve", "error", err)
		os.Exit(1)
	}
}

// startCandidateRetentionSweeper lanza una goroutine que ejecuta el sweeper
// de retención de candidate_parsers una vez al startup y luego cada 24h.
// Cuando el ctx se cancela (shutdown), la goroutine sale limpiamente.
func startCandidateRetentionSweeper(ctx context.Context, repo *notificationparser.CandidateRepository) {
	go func() {
		runOnce := func() {
			n, err := repo.PurgeOldSamples(ctx)
			if err != nil {
				slog.Error("candidate_parsers retention sweep failed", "error", err)
				return
			}
			if n > 0 {
				slog.Info("candidate_parsers retention sweep", "purged_rows", n)
			}
		}
		runOnce()
		t := time.NewTicker(24 * time.Hour)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				runOnce()
			}
		}
	}()
}
