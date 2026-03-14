package config

import (
	"fmt"
	"os"
)

type Config struct {
	DatabaseURL string
	GRPCPort    string
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
	return Config{DatabaseURL: dbURL, GRPCPort: port}, nil
}
