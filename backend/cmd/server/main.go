package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	"github.com/AlanIsaacV/pocket-pilot/internal/account"
	"github.com/AlanIsaacV/pocket-pilot/internal/category"
	"github.com/AlanIsaacV/pocket-pilot/internal/config"
	"github.com/AlanIsaacV/pocket-pilot/internal/database"
	"github.com/AlanIsaacV/pocket-pilot/internal/transaction"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()

	pool, err := database.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer pool.Close()
	log.Println("connected to PostgreSQL")

	// Wire up repositories and handlers
	accountHandler := account.NewHandler(account.NewRepository(pool))
	categoryHandler := category.NewHandler(category.NewRepository(pool))
	transactionHandler := transaction.NewHandler(transaction.NewRepository(pool))

	// gRPC server
	// In production you'd add interceptors here (logging, auth, recovery, etc.)
	srv := grpc.NewServer()
	pb.RegisterAccountServiceServer(srv, accountHandler)
	pb.RegisterCategoryServiceServer(srv, categoryHandler)
	pb.RegisterTransactionServiceServer(srv, transactionHandler)

	// Server Reflection lets grpcurl discover services without a .proto file:
	//   grpcurl -plaintext localhost:50051 list
	//   grpcurl -plaintext -d '{"user_id":"..."}' localhost:50051 pocket_pilot.v1.AccountService/ListAccounts
	reflection.Register(srv)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", cfg.GRPCPort))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	// Graceful shutdown on CTRL+C or SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-quit
		log.Println("shutting down...")
		srv.GracefulStop()
	}()

	log.Printf("gRPC server listening on :%s", cfg.GRPCPort)
	if err := srv.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
