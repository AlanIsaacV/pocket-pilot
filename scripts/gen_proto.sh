#!/usr/bin/env bash
# =============================================================================
# gen_proto.sh
# Compiles all .proto files for Go (backend) and Dart (Flutter frontend).
#
# PREREQUISITES — run this once before using the script:
#   See the "Guía de Instalación" section in this file below.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="${REPO_ROOT}/proto"

# Output directories
GO_OUT="${REPO_ROOT}/backend/internal/gen/proto/pocket_pilot/v1"
DART_OUT="${REPO_ROOT}/frontend/lib/src/generated"

echo "→ Creating output directories..."
mkdir -p "${GO_OUT}"
mkdir -p "${DART_OUT}"

echo "→ Generating Go code..."
# --go_out         : generates the message types (*.pb.go)
# --go-grpc_out    : generates the service client/server stubs (*_grpc.pb.go)
# paths=source_relative : output mirrors the proto directory structure,
#                         relative to the proto source file (not the cwd).
#                         This is almost always what you want.
protoc \
    --proto_path="${PROTO_DIR}" \
    --go_out="${GO_OUT}" \
    --go_opt=paths=source_relative \
    --go-grpc_out="${GO_OUT}" \
    --go-grpc_opt=paths=source_relative \
    pocket_pilot/v1/common.proto \
    pocket_pilot/v1/account_service.proto \
    pocket_pilot/v1/category_service.proto \
    pocket_pilot/v1/transaction_template_service.proto \
    pocket_pilot/v1/yield_config_service.proto \
    pocket_pilot/v1/transaction_service.proto \
    pocket_pilot/v1/tags_service.proto \
    pocket_pilot/v1/goal_service.proto \
    pocket_pilot/v1/user_preferences_service.proto \
    pocket_pilot/v1/budget_service.proto \
    pocket_pilot/v1/ai_assistant_service.proto \
    pocket_pilot/v1/auth_service.proto \
    pocket_pilot/v1/sync_service.proto \
    pocket_pilot/v1/investment_holding_service.proto \
    pocket_pilot/v1/investment_lot_service.proto \
    pocket_pilot/v1/investment_split_service.proto \
    pocket_pilot/v1/market_price_service.proto \
    pocket_pilot/v1/market_price_admin_service.proto

echo "→ Generating Dart code..."
# --dart_out=grpc:<dir>  : "grpc" is a plugin option that tells protoc_plugin
#                          to generate both message classes AND gRPC stubs.
#                          Without "grpc:", you'd only get message classes.
# -I (or --proto_path)   : tells protoc where to find imported .proto files.
#                          We need the repo proto dir AND the well-known types.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="grpc:${DART_OUT}" \
    pocket_pilot/v1/common.proto \
    pocket_pilot/v1/account_service.proto \
    pocket_pilot/v1/category_service.proto \
    pocket_pilot/v1/transaction_template_service.proto \
    pocket_pilot/v1/yield_config_service.proto \
    pocket_pilot/v1/transaction_service.proto \
    pocket_pilot/v1/tags_service.proto \
    pocket_pilot/v1/goal_service.proto \
    pocket_pilot/v1/user_preferences_service.proto \
    pocket_pilot/v1/budget_service.proto \
    pocket_pilot/v1/ai_assistant_service.proto \
    pocket_pilot/v1/auth_service.proto \
    pocket_pilot/v1/sync_service.proto \
    pocket_pilot/v1/investment_holding_service.proto \
    pocket_pilot/v1/investment_lot_service.proto \
    pocket_pilot/v1/investment_split_service.proto \
    pocket_pilot/v1/market_price_service.proto \
    pocket_pilot/v1/market_price_admin_service.proto

echo "✓ Done. Generated files:"
echo "  Go   → ${GO_OUT}"
echo "  Dart → ${DART_OUT}"

# =============================================================================
# GUÍA DE INSTALACIÓN DE PREREQUISITES
# =============================================================================
# Run these commands once to set up your local machine.
#
# 1. Install protoc (the Protocol Buffer compiler)
#    macOS:
#      brew install protobuf
#    Verify:
#      protoc --version  # should print: libprotoc 3.x or 4.x / 27.x+
#
# 2. Install the Go plugins for protoc
#    These are two separate binaries that protoc calls as subprocesses.
#
#      go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
#      go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
#
#    Then make sure your Go bin is on PATH (add to ~/.zshrc or ~/.config/fish/config.fish):
#      export PATH="$PATH:$(go env GOPATH)/bin"   # bash/zsh
#      fish_add_path (go env GOPATH)/bin           # fish
#
# 3. Install the Dart/Flutter plugin for protoc
#    The plugin is a Dart package installed globally via pub:
#
#      dart pub global activate protoc_plugin
#
#    Then add Dart's global bin to PATH:
#      export PATH="$PATH:$HOME/.pub-cache/bin"   # bash/zsh
#      fish_add_path $HOME/.pub-cache/bin          # fish
#
# 4. Initialize the Go module (only once):
#      cd backend/
#      go mod init github.com/AlanIsaacV/pocket-pilot/backend
#      go get google.golang.org/protobuf
#      go get google.golang.org/grpc
#
# 5. Initialize the Flutter project (only once):
#      cd frontend/
#      flutter create . --project-name pocket_pilot --org com.AlanIsaacV
#      flutter pub add grpc protobuf
#
# =============================================================================
