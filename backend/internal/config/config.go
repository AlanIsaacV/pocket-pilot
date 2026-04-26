package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL         string
	GRPCPort            string
	GeminiAPIKey        string
	AIDailyRequestLimit int
	AIMonthlyTokenLimit int

	// Modelo Gemini que usa cada feature. Se permiten distintos por feature
	// porque el chat suele beneficiarse de modelos rápidos/baratos
	// (gemini-3.1-flash) mientras que el notification_parser puede pedir
	// uno más capaz (p.ej. gemini-3.1-pro) para que el regex propuesto sea
	// más limpio. Default: gemini-3.1-flash-lite-preview en ambos para no
	// cambiar comportamiento al deployar mig 017.
	AIChatModel             string
	NotificationParserModel string

	// Cuota independiente para el LLM fallback de notification_capture.
	// El feature compite por capacidad/cuotas distintas a las del chat
	// porque las notis son cortas y se invocan sin acción explícita.
	NotificationParserDailyLimit        int
	NotificationParserMonthlyTokenLimit int

	GoogleClientID string
	AppleClientID  string
	JWTSecret      string

	// Market price cron (Fase 4 of investments).
	MarketPriceEnabled    bool
	MarketPriceRunOnBoot  bool
	MarketPriceProvider   string
	MarketPriceAdminToken string
}

func Load() (Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL environment variable is required")
	}

	port := os.Getenv("GRPC_PORT")
	if port == "" {
		port = "50051"
	}

	geminiKey := os.Getenv("GEMINI_API_KEY")
	if geminiKey == "" {
		return Config{}, fmt.Errorf("GEMINI_API_KEY environment variable is required")
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET environment variable is required")
	}

	dailyLimit := 50
	if v := os.Getenv("AI_DAILY_REQUEST_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			dailyLimit = n
		}
	}

	monthlyTokenLimit := 500_000
	if v := os.Getenv("AI_MONTHLY_TOKEN_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			monthlyTokenLimit = n
		}
	}

	notiDailyLimit := 50
	if v := os.Getenv("NOTIFICATION_PARSER_DAILY_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			notiDailyLimit = n
		}
	}

	notiMonthlyTokens := 200_000
	if v := os.Getenv("NOTIFICATION_PARSER_MONTHLY_TOKEN_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			notiMonthlyTokens = n
		}
	}

	// Default explícito para preservar comportamiento previo a esta config:
	// hasta antes de mig 017, el modelo era una constante hardcoded en el
	// provider. El default mantiene ese mismo modelo en ambos features.
	const defaultGeminiModel = "gemini-3.1-flash-lite-preview"
	chatModel := os.Getenv("AI_CHAT_MODEL")
	if chatModel == "" {
		chatModel = defaultGeminiModel
	}
	notiModel := os.Getenv("NOTIFICATION_PARSER_MODEL")
	if notiModel == "" {
		notiModel = defaultGeminiModel
	}

	marketProvider := os.Getenv("MARKETPRICE_PROVIDER")
	if marketProvider == "" {
		marketProvider = "yahoo"
	}

	return Config{
		DatabaseURL:                         dbURL,
		GRPCPort:                            port,
		GeminiAPIKey:                        geminiKey,
		AIDailyRequestLimit:                 dailyLimit,
		AIMonthlyTokenLimit:                 monthlyTokenLimit,
		AIChatModel:                         chatModel,
		NotificationParserModel:             notiModel,
		NotificationParserDailyLimit:        notiDailyLimit,
		NotificationParserMonthlyTokenLimit: notiMonthlyTokens,
		GoogleClientID:                      os.Getenv("GOOGLE_CLIENT_ID"),
		AppleClientID:                       os.Getenv("APPLE_CLIENT_ID"),
		JWTSecret:                           jwtSecret,
		MarketPriceEnabled:                  parseBoolEnv("MARKETPRICE_ENABLED", false),
		MarketPriceRunOnBoot:                parseBoolEnv("MARKETPRICE_RUN_ON_BOOT", false),
		MarketPriceProvider:                 marketProvider,
		MarketPriceAdminToken:               os.Getenv("MARKETPRICE_ADMIN_TOKEN"),
	}, nil
}

func parseBoolEnv(key string, fallback bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}
