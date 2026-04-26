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
