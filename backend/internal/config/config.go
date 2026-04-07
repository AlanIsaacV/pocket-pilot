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

	return Config{
		DatabaseURL:         dbURL,
		GRPCPort:            port,
		GeminiAPIKey:        geminiKey,
		AIDailyRequestLimit: dailyLimit,
		AIMonthlyTokenLimit: monthlyTokenLimit,
	}, nil
}
