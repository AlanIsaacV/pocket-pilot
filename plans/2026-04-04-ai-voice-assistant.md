# AI Voice Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a voice-activated AI assistant that lets users create transactions, execute templates, and query financial data by speaking, powered by Gemini via a stateless gRPC proxy backend.

**Architecture:** Flutter captures voice via STT, sends the full conversation history to a backend gRPC proxy that translates to Gemini's Function Calling API. Tool calls are executed locally against SQLite. Responses are read back via TTS. The backend is stateless — it validates auth, checks rate limits, injects the Gemini API key, and proxies the request. All business logic lives in Flutter.

**Tech Stack:** Protocol Buffers, Go (gRPC handler, Gemini REST adapter, PostgreSQL), Flutter/Dart (Provider/ChangeNotifier, sqflite, speech_to_text, flutter_tts)

**Spec:** `docs/superpowers/specs/2026-04-04-ai-voice-assistant-design.md`

**Pre-existing code this plan depends on (DO NOT create — verify they exist):**
- `frontend/lib/src/core/grpc/grpc_client.dart` — `GrpcClient.channel` static singleton + `AuthInterceptor` class
- `frontend/lib/src/core/theme/app_colors.dart` — `AppColors.surfaceDark`, `.primary`, `.error`, `.backgroundDark`
- `frontend/lib/src/core/db/database_helper.dart` — `DatabaseHelper` singleton with `Future<Database> get database`
- `frontend/lib/src/core/sync/sync_outbox.dart` — `SyncOutbox` with `enqueue()`
- `frontend/lib/src/features/transactions/data/transaction_repository.dart` — `TransactionRepository` with `createTransaction()`, `createTransfer()`
- `frontend/lib/src/features/transactions/data/transaction_local_store.dart` — `TransactionLocalStore`
- `frontend/lib/src/features/accounts/data/account_local_store.dart` — `AccountLocalStore` with `getAccounts()`
- `frontend/lib/src/features/categories/data/category_local_store.dart` — `CategoryLocalStore` with `getCategories()`
- `frontend/lib/src/features/transaction_templates/data/transaction_template_local_store.dart` — `TransactionTemplateLocalStore` with `queryRows()`
- `frontend/lib/src/features/goals/data/goal_local_store.dart` — `GoalLocalStore` with `queryRows()`
- `frontend/lib/src/features/user_preferences/data/user_preference_local_store.dart` — `UserPreferenceLocalStore` with `getByKey()`
- `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` — `DashboardLocalStore` with `getBalancesPerAccount()`, `getMonthlySpendByCategory()`
- `frontend/lib/src/features/dashboard/data/dashboard_repository.dart` — `DashboardRepository` with `calculateAllMetrics()`
- `frontend/lib/src/features/transaction_templates/domain/transaction_template.dart` — `TransactionTemplateModel.fromMap()`
- `frontend/lib/src/features/goals/domain/goal.dart` — `GoalModel.fromMap()`
- `backend/internal/middleware/` — `middleware.UserIDFromCtx(ctx)` extracts user_id from gRPC context
- Proto import path in Go: `pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"` (this doubled path is correct — the proto generation outputs to this structure)
- Proto-generated Dart fields: proto `tool_call` → Dart `toolCall`, proto `tool_call_id` → Dart `toolCallId` (standard protoc camelCase conversion)
- `uuid` package is already in pubspec.yaml (used by existing features for client-generated UUIDs)

---

## File Map

### Proto (new)
- `proto/pocket_pilot/v1/ai_assistant_service.proto` — service, messages, enums

### Backend (new)
- `backend/internal/aiassistant/handler.go` — gRPC handler
- `backend/internal/aiassistant/provider.go` — `LLMProvider` interface + `GeminiProvider`
- `backend/internal/aiassistant/rate_limiter.go` — daily/monthly limit checks
- `backend/internal/aiassistant/repository.go` — `ai_usage` PostgreSQL queries
- `backend/internal/aiassistant/domain.go` — internal domain structs
- `backend/migrations/002_ai_usage.sql` — migration

### Backend (modify)
- `backend/internal/config/config.go` — add Gemini API key + rate limit env vars
- `backend/cmd/server/main.go` — register `AIAssistantServiceServer`

### Frontend (new)
- `frontend/lib/src/features/ai_assistant/domain/ai_tool_result.dart`
- `frontend/lib/src/features/ai_assistant/domain/ai_tool_definitions.dart`
- `frontend/lib/src/features/ai_assistant/data/ai_remote_service.dart`
- `frontend/lib/src/features/ai_assistant/data/tools/transaction_tool.dart`
- `frontend/lib/src/features/ai_assistant/data/tools/template_tool.dart`
- `frontend/lib/src/features/ai_assistant/data/tools/financial_summary_tool.dart`
- `frontend/lib/src/features/ai_assistant/data/tools/goal_tool.dart`
- `frontend/lib/src/features/ai_assistant/data/tools/unsupported_tool.dart`
- `frontend/lib/src/features/ai_assistant/data/ai_tool_dispatcher.dart`
- `frontend/lib/src/features/ai_assistant/data/ai_context_builder.dart`
- `frontend/lib/src/features/ai_assistant/ui/ai_session_controller.dart`
- `frontend/lib/src/features/ai_assistant/ui/ai_overlay.dart`

### Frontend (modify)
- `frontend/lib/main.dart` — add AI assistant providers above router
- `frontend/pubspec.yaml` — add `speech_to_text` and `flutter_tts` dependencies

---

## Task 1: Proto Contract — `ai_assistant_service.proto`

**Files:**
- Create: `proto/pocket_pilot/v1/ai_assistant_service.proto`

- [ ] **Step 1: Create the proto file**

```protobuf
syntax = "proto3";

package pocket_pilot.v1;

option go_package = "github.com/AlanIsaacV/pocket-pilot/backend/internal/gen/proto/pocket_pilot/v1;pocketpilotv1";

enum AIRole {
  AI_ROLE_UNSPECIFIED = 0;
  AI_ROLE_SYSTEM = 1;
  AI_ROLE_USER = 2;
  AI_ROLE_ASSISTANT = 3;
  AI_ROLE_TOOL = 4;
}

message AIToolCall {
  string id = 1;
  string name = 2;
  string arguments = 3;
}

message AIMessage {
  AIRole role = 1;
  string content = 2;
  optional string tool_call_id = 3;
  optional AIToolCall tool_call = 4;
}

message AIToolDefinition {
  string name = 1;
  string description = 2;
  string parameters_schema = 3;
}

message AIUsageMetadata {
  int32 prompt_tokens = 1;
  int32 completion_tokens = 2;
  int32 total_tokens = 3;
}

message AIChatRequest {
  repeated AIMessage messages = 1;
  repeated AIToolDefinition tools = 2;
}

message AIChatResponse {
  oneof response {
    string text = 1;
    AIToolCall tool_call = 2;
  }
  AIUsageMetadata usage = 3;
}

service AIAssistantService {
  rpc Chat(AIChatRequest) returns (AIChatResponse);
}
```

- [ ] **Step 2: Generate Go + Dart code**

Run: `make proto` (or `bash scripts/gen_proto.sh`)

Expected: New generated files appear in:
- `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/ai_assistant_service.pb.go`
- `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/ai_assistant_service_grpc.pb.go`
- `frontend/lib/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart`
- `frontend/lib/src/generated/pocket_pilot/v1/ai_assistant_service.pbgrpc.dart`

- [ ] **Step 3: Verify generation compiled cleanly**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter pub get`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add proto/pocket_pilot/v1/ai_assistant_service.proto
git add backend/internal/gen/
git add frontend/lib/src/generated/
git commit -m "feat(proto): add AIAssistantService contract for voice assistant"
```

---

## Task 2: Backend — Config, Migration, Domain

**Files:**
- Modify: `backend/internal/config/config.go`
- Create: `backend/migrations/002_ai_usage.sql`
- Create: `backend/internal/aiassistant/domain.go`

- [ ] **Step 1: Add new config fields**

Add to `config.go` after the existing `GRPCPort` field in the `Config` struct and the `Load` function:

```go
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
```

Note: add `"strconv"` to the imports.

- [ ] **Step 2: Create migration file**

Create `backend/migrations/002_ai_usage.sql`:

```sql
CREATE TABLE ai_usage (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID         NOT NULL,
    prompt_tokens       INT          NOT NULL,
    completion_tokens   INT          NOT NULL,
    total_tokens        INT          NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX idx_ai_usage_user_daily ON ai_usage (user_id, created_at);
```

- [ ] **Step 3: Create domain structs**

Create `backend/internal/aiassistant/domain.go`:

```go
package aiassistant

import (
	"time"

	"github.com/google/uuid"
)

// UsageRecord represents one AI API call for billing/rate-limiting.
type UsageRecord struct {
	ID               uuid.UUID
	UserID           uuid.UUID
	PromptTokens     int
	CompletionTokens int
	TotalTokens      int
	CreatedAt        time.Time
}

// LLMResponse is the provider-agnostic response from an LLM.
type LLMResponse struct {
	// Text is set when the LLM responds with text.
	Text string
	// ToolCall is set when the LLM requests a function call.
	ToolCall *LLMToolCall
	// Usage contains token counts for rate limiting.
	Usage LLMUsage
}

type LLMToolCall struct {
	ID        string
	Name      string
	Arguments string // JSON string
}

type LLMUsage struct {
	PromptTokens     int
	CompletionTokens int
	TotalTokens      int
}
```

- [ ] **Step 4: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/config/config.go
git add backend/migrations/002_ai_usage.sql
git add backend/internal/aiassistant/domain.go
git commit -m "feat(backend): add AI config, migration, and domain types"
```

---

## Task 3: Backend — Repository (Usage Tracking)

**Files:**
- Create: `backend/internal/aiassistant/repository.go`

- [ ] **Step 1: Create repository**

```go
package aiassistant

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// RecordUsage inserts a new usage entry after a successful LLM call.
func (r *Repository) RecordUsage(ctx context.Context, userID uuid.UUID, prompt, completion int) error {
	total := prompt + completion
	_, err := r.pool.Exec(ctx, `
		INSERT INTO ai_usage (id, user_id, prompt_tokens, completion_tokens, total_tokens, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
	`, uuid.New(), userID, prompt, completion, total)
	return err
}

// CountRequestsToday returns the number of AI requests the user has made today.
func (r *Repository) CountRequestsToday(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM ai_usage
		WHERE user_id = $1 AND created_at >= current_date
	`, userID).Scan(&count)
	return count, err
}

// SumTokensThisMonth returns the total tokens consumed by the user this month.
func (r *Repository) SumTokensThisMonth(ctx context.Context, userID uuid.UUID) (int, error) {
	var total int
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(total_tokens), 0) FROM ai_usage
		WHERE user_id = $1 AND created_at >= date_trunc('month', now())
	`, userID).Scan(&total)
	return total, err
}

// UsageStats holds the current usage for rate limit checks.
type UsageStats struct {
	DailyRequests int
	MonthlyTokens int
	AsOf          time.Time
}

// GetUsageStats fetches both daily requests and monthly tokens in two queries.
func (r *Repository) GetUsageStats(ctx context.Context, userID uuid.UUID) (*UsageStats, error) {
	daily, err := r.CountRequestsToday(ctx, userID)
	if err != nil {
		return nil, err
	}
	monthly, err := r.SumTokensThisMonth(ctx, userID)
	if err != nil {
		return nil, err
	}
	return &UsageStats{
		DailyRequests: daily,
		MonthlyTokens: monthly,
		AsOf:          time.Now().UTC(),
	}, nil
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/aiassistant/repository.go
git commit -m "feat(backend): add AI usage repository with rate limit queries"
```

---

## Task 4: Backend — Rate Limiter

**Files:**
- Create: `backend/internal/aiassistant/rate_limiter.go`

- [ ] **Step 1: Create rate limiter**

```go
package aiassistant

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type RateLimiter struct {
	repo              *Repository
	dailyRequestLimit int
	monthlyTokenLimit int
}

func NewRateLimiter(repo *Repository, dailyRequestLimit, monthlyTokenLimit int) *RateLimiter {
	return &RateLimiter{
		repo:              repo,
		dailyRequestLimit: dailyRequestLimit,
		monthlyTokenLimit: monthlyTokenLimit,
	}
}

// Check returns a gRPC RESOURCE_EXHAUSTED error if the user has exceeded
// either the daily request limit or the monthly token limit.
func (rl *RateLimiter) Check(ctx context.Context, userID uuid.UUID) error {
	stats, err := rl.repo.GetUsageStats(ctx, userID)
	if err != nil {
		return fmt.Errorf("rate limiter: %w", err)
	}

	if stats.DailyRequests >= rl.dailyRequestLimit {
		return status.Errorf(codes.ResourceExhausted,
			"Has alcanzado tu límite diario de %d solicitudes. Intenta mañana.",
			rl.dailyRequestLimit)
	}

	if stats.MonthlyTokens >= rl.monthlyTokenLimit {
		return status.Errorf(codes.ResourceExhausted,
			"Has alcanzado tu límite mensual de tokens. El límite se reinicia el próximo mes.")
	}

	return nil
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/aiassistant/rate_limiter.go
git commit -m "feat(backend): add AI rate limiter with daily/monthly limits"
```

---

## Task 5: Backend — Gemini Provider

**Files:**
- Create: `backend/internal/aiassistant/provider.go`

- [ ] **Step 1: Create provider interface and Gemini implementation**

The Gemini REST API endpoint for `generateContent` is:
`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}`

We'll use `net/http` + `encoding/json` directly (no SDK dependency needed for a single endpoint).

```go
package aiassistant

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// LLMProvider is the interface for any LLM backend.
type LLMProvider interface {
	Chat(ctx context.Context, messages []*AIMessageInput, tools []*AIToolInput) (*LLMResponse, error)
}

// AIMessageInput is the provider-agnostic input message.
type AIMessageInput struct {
	Role       string
	Content    string
	ToolCallID string // only for role=tool
	ToolCall   *LLMToolCall // only for role=assistant with tool call
}

// AIToolInput is the provider-agnostic tool definition.
type AIToolInput struct {
	Name             string
	Description      string
	ParametersSchema string // JSON Schema string
}

// ── Gemini Provider ─────────────────────────────────────────────────────────

const (
	geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"
	geminiModel   = "gemini-2.0-flash"
)

type GeminiProvider struct {
	apiKey     string
	httpClient *http.Client
}

func NewGeminiProvider(apiKey string) *GeminiProvider {
	return &GeminiProvider{
		apiKey:     apiKey,
		httpClient: &http.Client{},
	}
}

func (g *GeminiProvider) Chat(ctx context.Context, messages []*AIMessageInput, tools []*AIToolInput) (*LLMResponse, error) {
	body := g.buildRequest(messages, tools)

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("gemini marshal: %w", err)
	}

	url := fmt.Sprintf("%s/%s:generateContent?key=%s", geminiBaseURL, geminiModel, g.apiKey)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("gemini request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := g.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini call: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("gemini read: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	return g.parseResponse(respBody)
}

// ── Gemini Request Building ─────────────────────────────────────────────────

func (g *GeminiProvider) buildRequest(messages []*AIMessageInput, tools []*AIToolInput) map[string]any {
	contents := g.buildContents(messages)

	req := map[string]any{
		"contents": contents,
		"generationConfig": map[string]any{
			"temperature": 0.1,
		},
	}

	// System instruction (extracted from first message if role=system)
	if len(messages) > 0 && messages[0].Role == "system" {
		req["systemInstruction"] = map[string]any{
			"parts": []map[string]any{
				{"text": messages[0].Content},
			},
		}
	}

	// Tools
	if len(tools) > 0 {
		funcDecls := make([]map[string]any, 0, len(tools))
		for _, t := range tools {
			var params map[string]any
			_ = json.Unmarshal([]byte(t.ParametersSchema), &params)
			funcDecls = append(funcDecls, map[string]any{
				"name":        t.Name,
				"description": t.Description,
				"parameters":  params,
			})
		}
		req["tools"] = []map[string]any{
			{"functionDeclarations": funcDecls},
		}
		req["toolConfig"] = map[string]any{
			"functionCallingConfig": map[string]any{
				"mode": "AUTO",
			},
		}
	}

	return req
}

func (g *GeminiProvider) buildContents(messages []*AIMessageInput) []map[string]any {
	var contents []map[string]any

	for _, msg := range messages {
		switch msg.Role {
		case "system":
			// Handled separately as systemInstruction
			continue

		case "user":
			contents = append(contents, map[string]any{
				"role":  "user",
				"parts": []map[string]any{{"text": msg.Content}},
			})

		case "assistant":
			if msg.ToolCall != nil {
				// Assistant requested a function call
				var args map[string]any
				_ = json.Unmarshal([]byte(msg.ToolCall.Arguments), &args)
				contents = append(contents, map[string]any{
					"role": "model",
					"parts": []map[string]any{
						{
							"functionCall": map[string]any{
								"name": msg.ToolCall.Name,
								"args": args,
							},
						},
					},
				})
			} else {
				contents = append(contents, map[string]any{
					"role":  "model",
					"parts": []map[string]any{{"text": msg.Content}},
				})
			}

		case "tool":
			// Function response
			var result map[string]any
			_ = json.Unmarshal([]byte(msg.Content), &result)
			if result == nil {
				result = map[string]any{"result": msg.Content}
			}
			contents = append(contents, map[string]any{
				"role": "function",
				"parts": []map[string]any{
					{
						"functionResponse": map[string]any{
							"name":     msg.ToolCallID,
							"response": result,
						},
					},
				},
			})
		}
	}

	return contents
}

// ── Gemini Response Parsing ─────────────────────────────────────────────────

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text         string `json:"text,omitempty"`
				FunctionCall *struct {
					Name string         `json:"name"`
					Args map[string]any `json:"args"`
				} `json:"functionCall,omitempty"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	UsageMetadata struct {
		PromptTokenCount     int `json:"promptTokenCount"`
		CandidatesTokenCount int `json:"candidatesTokenCount"`
		TotalTokenCount      int `json:"totalTokenCount"`
	} `json:"usageMetadata"`
}

func (g *GeminiProvider) parseResponse(body []byte) (*LLMResponse, error) {
	var resp geminiResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("gemini parse: %w", err)
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("gemini: empty response")
	}

	result := &LLMResponse{
		Usage: LLMUsage{
			PromptTokens:     resp.UsageMetadata.PromptTokenCount,
			CompletionTokens: resp.UsageMetadata.CandidatesTokenCount,
			TotalTokens:      resp.UsageMetadata.TotalTokenCount,
		},
	}

	part := resp.Candidates[0].Content.Parts[0]
	if part.FunctionCall != nil {
		argsJSON, _ := json.Marshal(part.FunctionCall.Args)
		result.ToolCall = &LLMToolCall{
			ID:        fmt.Sprintf("call_%s", part.FunctionCall.Name),
			Name:      part.FunctionCall.Name,
			Arguments: string(argsJSON),
		}
	} else {
		result.Text = part.Text
	}

	return result, nil
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/aiassistant/provider.go
git commit -m "feat(backend): add Gemini LLM provider with function calling"
```

---

## Task 6: Backend — Handler + Registration

**Files:**
- Create: `backend/internal/aiassistant/handler.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Create handler**

```go
package aiassistant

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

type Handler struct {
	pb.UnimplementedAIAssistantServiceServer
	provider    LLMProvider
	rateLimiter *RateLimiter
	repo        *Repository
}

func NewHandler(provider LLMProvider, rateLimiter *RateLimiter, repo *Repository) *Handler {
	return &Handler{
		provider:    provider,
		rateLimiter: rateLimiter,
		repo:        repo,
	}
}

func (h *Handler) Chat(ctx context.Context, req *pb.AIChatRequest) (*pb.AIChatResponse, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	// Rate limit check
	if err := h.rateLimiter.Check(ctx, userID); err != nil {
		return nil, err
	}

	// Convert proto messages to provider-agnostic inputs
	messages := make([]*AIMessageInput, 0, len(req.Messages))
	for _, m := range req.Messages {
		msg := &AIMessageInput{
			Role:    aiRoleToString(m.Role),
			Content: m.Content,
		}
		if m.ToolCallId != nil {
			msg.ToolCallID = *m.ToolCallId
		}
		if m.ToolCall != nil {
			msg.ToolCall = &LLMToolCall{
				ID:        m.ToolCall.Id,
				Name:      m.ToolCall.Name,
				Arguments: m.ToolCall.Arguments,
			}
		}
		messages = append(messages, msg)
	}

	tools := make([]*AIToolInput, 0, len(req.Tools))
	for _, t := range req.Tools {
		tools = append(tools, &AIToolInput{
			Name:             t.Name,
			Description:      t.Description,
			ParametersSchema: t.ParametersSchema,
		})
	}

	// Call LLM
	llmResp, err := h.provider.Chat(ctx, messages, tools)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "llm error: %v", err)
	}

	// Record usage
	if err := h.repo.RecordUsage(ctx, userID, llmResp.Usage.PromptTokens, llmResp.Usage.CompletionTokens); err != nil {
		// Log but don't fail the request — usage recording is best-effort
		_ = err
	}

	// Build response
	resp := &pb.AIChatResponse{
		Usage: &pb.AIUsageMetadata{
			PromptTokens:     int32(llmResp.Usage.PromptTokens),
			CompletionTokens: int32(llmResp.Usage.CompletionTokens),
			TotalTokens:      int32(llmResp.Usage.TotalTokens),
		},
	}

	if llmResp.ToolCall != nil {
		resp.Response = &pb.AIChatResponse_ToolCall{
			ToolCall: &pb.AIToolCall{
				Id:        llmResp.ToolCall.ID,
				Name:      llmResp.ToolCall.Name,
				Arguments: llmResp.ToolCall.Arguments,
			},
		}
	} else {
		resp.Response = &pb.AIChatResponse_Text{
			Text: llmResp.Text,
		}
	}

	return resp, nil
}

func aiRoleToString(role pb.AIRole) string {
	switch role {
	case pb.AIRole_AI_ROLE_SYSTEM:
		return "system"
	case pb.AIRole_AI_ROLE_USER:
		return "user"
	case pb.AIRole_AI_ROLE_ASSISTANT:
		return "assistant"
	case pb.AIRole_AI_ROLE_TOOL:
		return "tool"
	default:
		return "user"
	}
}
```

- [ ] **Step 2: Register in main.go**

Add the import to the import block in `backend/cmd/server/main.go`:

```go
"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
```

After the existing handler wiring (line ~54, after `userPreferenceHandler`), add:

```go
// AI Assistant
geminiProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey)
aiRepo := aiassistant.NewRepository(pool)
aiRateLimiter := aiassistant.NewRateLimiter(aiRepo, cfg.AIDailyRequestLimit, cfg.AIMonthlyTokenLimit)
aiHandler := aiassistant.NewHandler(geminiProvider, aiRateLimiter, aiRepo)
```

After the existing service registrations (line ~69, after `RegisterUserPreferenceServiceServer`), add:

```go
pb.RegisterAIAssistantServiceServer(srv, aiHandler)
```

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/aiassistant/handler.go
git add backend/cmd/server/main.go
git commit -m "feat(backend): add AI assistant handler and register gRPC service"
```

---

## Task 7: Frontend — Domain Models + Remote Service

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/domain/ai_tool_result.dart`
- Create: `frontend/lib/src/features/ai_assistant/data/ai_remote_service.dart`

- [ ] **Step 1: Create AIToolResult**

```dart
class AIToolResult {
  final bool success;
  final String content;

  const AIToolResult({
    required this.success,
    required this.content,
  });
}
```

- [ ] **Step 2: Create AIRemoteService**

```dart
import 'package:grpc/grpc.dart';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart'; // GrpcClient + AuthInterceptor
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pbgrpc.dart';

class AIRemoteService {
  late final AIAssistantServiceClient _client;

  AIRemoteService() {
    _client = AIAssistantServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  /// Sends the full conversation history + tool definitions to the backend.
  /// Returns the raw [AIChatResponse] for the caller to interpret.
  /// Throws [GrpcError] on network or rate-limit errors.
  Future<AIChatResponse> chat({
    required List<AIMessage> messages,
    required List<AIToolDefinition> tools,
  }) async {
    final request = AIChatRequest(
      messages: messages,
      tools: tools,
    );
    return await _client.chat(request);
  }
}
```

Note: `AuthInterceptor` is imported from `package:pocket_pilot/src/core/grpc/grpc_client.dart` (it's in the same file as `GrpcClient`).

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors from the new files.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/domain/ai_tool_result.dart
git add frontend/lib/src/features/ai_assistant/data/ai_remote_service.dart
git commit -m "feat(frontend): add AI domain models and gRPC remote service"
```

---

## Task 8: Frontend — Tool Definitions (Constants)

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/domain/ai_tool_definitions.dart`

- [ ] **Step 1: Create tool definitions as constants**

These are the `AIToolDefinition` objects sent with every request. They define the JSON Schema the LLM uses to structure its function calls.

```dart
import 'dart:convert';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart';

/// All AI tool definitions sent with every Chat request.
/// The LLM uses these schemas to decide which function to call and
/// how to structure its arguments.
List<AIToolDefinition> get aiToolDefinitions => [
      _gestionarTransaccion,
      _ejecutarPlantilla,
      _consultarResumenFinanciero,
      _gestionarMeta,
      _reportarFuncionNoSoportada,
    ];

final _gestionarTransaccion = AIToolDefinition(
  name: 'gestionar_transaccion',
  description:
      'Crea una nueva transacción financiera (ingreso, gasto o transferencia entre cuentas).',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['income', 'expense', 'transfer_out'],
      },
      'account_id': {
        'type': 'string',
        'description': 'ID de la cuenta origen',
      },
      'to_account_id': {
        'type': 'string',
        'description': 'ID de la cuenta destino (solo para transferencias)',
      },
      'amount_cents': {
        'type': 'integer',
        'description': 'Monto en centavos',
      },
      'currency_code': {
        'type': 'string',
        'description': 'Código de moneda (ej: MXN)',
      },
      'category_id': {
        'type': 'string',
        'description': 'ID de la categoría (no aplica para transferencias)',
      },
      'description': {'type': 'string'},
      'date': {
        'type': 'string',
        'format': 'date',
        'description': 'Fecha en formato YYYY-MM-DD',
      },
    },
    'required': ['type', 'account_id', 'amount_cents', 'currency_code', 'date'],
  }),
);

final _ejecutarPlantilla = AIToolDefinition(
  name: 'ejecutar_plantilla',
  description:
      'Busca una plantilla de transacción por nombre y crea la transacción con los valores predefinidos.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'template_name': {
        'type': 'string',
        'description': 'Nombre de la plantilla a ejecutar',
      },
    },
    'required': ['template_name'],
  }),
);

final _consultarResumenFinanciero = AIToolDefinition(
  name: 'consultar_resumen_financiero',
  description:
      'Consulta datos financieros del usuario: saldos, gastos, ingresos, métricas del dashboard.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'query_type': {
        'type': 'string',
        'enum': [
          'account_balance',
          'monthly_expenses',
          'monthly_income',
          'category_expenses',
          'buying_power',
          'liquidity',
        ],
        'description': 'Tipo de consulta financiera',
      },
      'account_id': {
        'type': 'string',
        'description': 'ID de cuenta (opcional, para filtrar)',
      },
      'category_id': {
        'type': 'string',
        'description': 'ID de categoría (opcional, para filtrar)',
      },
      'period': {
        'type': 'string',
        'pattern': r'^\d{4}-\d{2}$',
        'description': 'Mes en formato YYYY-MM (default: mes actual)',
      },
    },
    'required': ['query_type'],
  }),
);

final _gestionarMeta = AIToolDefinition(
  name: 'gestionar_meta',
  description:
      'Consulta el estado de una meta de ahorro: progreso, monto faltante, fecha límite.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'goal_id': {
        'type': 'string',
        'description': 'ID de la meta',
      },
      'goal_name': {
        'type': 'string',
        'description': 'Nombre de la meta (alternativa al ID)',
      },
    },
    'anyOf': [
      {'required': ['goal_id']},
      {'required': ['goal_name']},
    ],
  }),
);

final _reportarFuncionNoSoportada = AIToolDefinition(
  name: 'reportar_funcion_no_soportada',
  description:
      'Usa esta herramienta cuando el usuario pida algo que no puedes hacer con las herramientas disponibles. Registra la intención para análisis futuro.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'user_intent': {
        'type': 'string',
        'description': 'Descripción de lo que el usuario intentó hacer',
      },
      'reason': {
        'type': 'string',
        'description': 'Por qué no se puede cumplir la solicitud',
      },
    },
    'required': ['user_intent', 'reason'],
  }),
);
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/domain/ai_tool_definitions.dart
git commit -m "feat(frontend): add AI tool definitions with JSON schemas"
```

---

## Task 9: Frontend — Tool Handlers (transaction, template, unsupported)

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/data/tools/transaction_tool.dart`
- Create: `frontend/lib/src/features/ai_assistant/data/tools/template_tool.dart`
- Create: `frontend/lib/src/features/ai_assistant/data/tools/unsupported_tool.dart`

- [ ] **Step 1: Create TransactionTool**

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class TransactionTool {
  final TransactionRepository _repo;

  TransactionTool({required TransactionRepository repo}) : _repo = repo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final type = args['type'] as String;
      final accountId = args['account_id'] as String;
      final amountCents = (args['amount_cents'] as num).toInt();
      final currencyCode = args['currency_code'] as String;
      final date = args['date'] as String;
      final description = args['description'] as String? ?? '';
      final categoryId = args['category_id'] as String?;

      if (type == 'transfer_out') {
        final toAccountId = args['to_account_id'] as String?;
        if (toAccountId == null) {
          return const AIToolResult(
            success: false,
            content: '{"error": "to_account_id es requerido para transferencias"}',
          );
        }

        final outId = const Uuid().v4();
        final inId = const Uuid().v4();

        await _repo.createTransfer(
          outId: outId,
          inId: inId,
          fromAccountId: accountId,
          toAccountId: toAccountId,
          amountOutCents: amountCents,
          currencyOut: currencyCode,
          amountInCents: amountCents,
          currencyIn: currencyCode,
          date: date,
          descriptionOut: description,
          descriptionIn: description,
          tags: const [],
        );

        return AIToolResult(
          success: true,
          content: jsonEncode({
            'message': 'Transferencia creada',
            'out_id': outId,
            'in_id': inId,
          }),
        );
      }

      // income or expense
      final id = const Uuid().v4();
      await _repo.createTransaction(
        id: id,
        accountId: accountId,
        categoryId: categoryId,
        amountMinor: amountCents,
        currencyCode: currencyCode,
        description: description,
        date: date,
        type: type,
        status: 'cleared',
        tags: const [],
      );

      return AIToolResult(
        success: true,
        content: jsonEncode({'message': 'Transacción creada', 'id': id}),
      );
    } catch (e) {
      dev.log('TransactionTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al crear transacción: $e'}),
      );
    }
  }
}
```

- [ ] **Step 2: Create TemplateTool**

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class TemplateTool {
  final DatabaseHelper _db;
  final TransactionRepository _transactionRepo;

  TemplateTool({
    required DatabaseHelper db,
    required TransactionRepository transactionRepo,
  }) : _db = db,
       _transactionRepo = transactionRepo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final templateName = args['template_name'] as String;

      // Case-insensitive LIKE search
      final db = await _db.database;
      final rows = await db.query(
        'transaction_templates',
        where: "deleted_at IS NULL AND name LIKE ?",
        whereArgs: ['%$templateName%'],
        orderBy: 'name ASC',
        limit: 5,
      );

      if (rows.isEmpty) {
        // Suggest available templates
        final allRows = await db.query(
          'transaction_templates',
          columns: ['name'],
          where: 'deleted_at IS NULL',
          orderBy: 'name ASC',
        );
        final names = allRows.map((r) => r['name'] as String).toList();
        return AIToolResult(
          success: false,
          content: jsonEncode({
            'error': 'No se encontró una plantilla con ese nombre',
            'available_templates': names,
          }),
        );
      }

      // Use first match
      final template = TransactionTemplateModel.fromMap(rows.first);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      if (template.type == 'transfer_out' && template.toAccountId != null) {
        final outId = const Uuid().v4();
        final inId = const Uuid().v4();
        await _transactionRepo.createTransfer(
          outId: outId,
          inId: inId,
          fromAccountId: template.accountId,
          toAccountId: template.toAccountId!,
          amountOutCents: template.amountCents ?? 0,
          currencyOut: template.currencyCode,
          amountInCents: template.amountCents ?? 0,
          currencyIn: template.currencyCode,
          date: date,
          descriptionOut: template.name,
          descriptionIn: template.name,
          tags: template.tags,
        );
        return AIToolResult(
          success: true,
          content: jsonEncode({
            'message': 'Transferencia creada desde plantilla "${template.name}"',
            'out_id': outId,
            'in_id': inId,
          }),
        );
      }

      final id = const Uuid().v4();
      await _transactionRepo.createTransaction(
        id: id,
        accountId: template.accountId,
        categoryId: template.categoryId,
        templateId: template.id,
        amountMinor: template.amountCents ?? 0,
        currencyCode: template.currencyCode,
        description: template.name,
        date: date,
        type: template.type,
        status: 'cleared',
        tags: template.tags,
      );

      return AIToolResult(
        success: true,
        content: jsonEncode({
          'message': 'Transacción creada desde plantilla "${template.name}"',
          'id': id,
        }),
      );
    } catch (e) {
      dev.log('TemplateTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al ejecutar plantilla: $e'}),
      );
    }
  }
}
```

- [ ] **Step 3: Create UnsupportedTool**

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';

class UnsupportedTool {
  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    final intent = args['user_intent'] as String? ?? 'unknown';
    final reason = args['reason'] as String? ?? 'unknown';

    dev.log('UnsupportedTool: intent="$intent", reason="$reason"');

    return AIToolResult(
      success: false,
      content: jsonEncode({
        'error': 'Función no soportada',
        'user_intent': intent,
        'reason': reason,
      }),
    );
  }
}
```

- [ ] **Step 4: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors from the new files. The `uuid` package is already in pubspec.yaml (used by existing features).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/data/tools/transaction_tool.dart
git add frontend/lib/src/features/ai_assistant/data/tools/template_tool.dart
git add frontend/lib/src/features/ai_assistant/data/tools/unsupported_tool.dart
git commit -m "feat(frontend): add transaction, template, and unsupported tool handlers"
```

---

## Task 10: Frontend — Tool Handlers (financial summary, goal)

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/data/tools/financial_summary_tool.dart`
- Create: `frontend/lib/src/features/ai_assistant/data/tools/goal_tool.dart`

- [ ] **Step 1: Create FinancialSummaryTool**

This tool reuses `DashboardRepository` and `DashboardLocalStore` for the heavy queries.

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';

class FinancialSummaryTool {
  final DashboardRepository _dashboardRepo;
  final DashboardLocalStore _dashboardLocal;

  FinancialSummaryTool({
    required DashboardRepository dashboardRepo,
    required DashboardLocalStore dashboardLocal,
  }) : _dashboardRepo = dashboardRepo,
       _dashboardLocal = dashboardLocal;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final queryType = args['query_type'] as String;
      final accountId = args['account_id'] as String?;
      final categoryId = args['category_id'] as String?;
      final period = args['period'] as String?; // YYYY-MM

      final now = DateTime.now();
      final year = period != null ? int.parse(period.split('-')[0]) : now.year;
      final month = period != null ? int.parse(period.split('-')[1]) : now.month;
      final startDate =
          '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay = DateTime(year, month + 1, 0).day;
      final endDate =
          '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

      final accountIds = accountId != null ? {accountId} : null;

      switch (queryType) {
        case 'account_balance':
          final balances = await _dashboardLocal.getBalancesPerAccount(
            accountIds: accountIds,
          );
          final data = balances.map((b) => {
            return {
              'account_name': b.accountName,
              'account_type': b.accountType,
              'balance_cents': b.balanceCents,
              'currency_code': b.currencyCode,
            };
          }).toList();
          return AIToolResult(
            success: true,
            content: jsonEncode({'balances': data}),
          );

        case 'monthly_expenses':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          final expenseOnly =
              spends.where((s) => s.spentCents > 0).toList();
          final totalCents =
              expenseOnly.fold<int>(0, (sum, s) => sum + s.spentCents);
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'total_expense_cents': totalCents,
              'by_category': expenseOnly.map((s) => {
                return {
                  'category_name': s.categoryName ?? 'Sin categoría',
                  'spent_cents': s.spentCents,
                  'currency_code': s.currencyCode,
                };
              }).toList(),
            }),
          );

        case 'monthly_income':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          // Income shows as negative spent_cents in the query
          final incomeOnly =
              spends.where((s) => s.spentCents < 0).toList();
          final totalCents =
              incomeOnly.fold<int>(0, (sum, s) => sum + s.spentCents.abs());
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'total_income_cents': totalCents,
            }),
          );

        case 'category_expenses':
          final spends = await _dashboardLocal.getMonthlySpendByCategory(
            startDate,
            endDate,
            accountIds: accountIds,
          );
          List filtered = spends.where((s) => s.spentCents > 0).toList();
          if (categoryId != null) {
            filtered = filtered
                .where((s) => s.categoryId == categoryId)
                .toList();
          }
          return AIToolResult(
            success: true,
            content: jsonEncode({
              'period': '$year-${month.toString().padLeft(2, '0')}',
              'categories': filtered.map((s) => {
                return {
                  'category_id': s.categoryId,
                  'category_name': s.categoryName ?? 'Sin categoría',
                  'spent_cents': s.spentCents,
                  'currency_code': s.currencyCode,
                };
              }).toList(),
            }),
          );

        case 'buying_power':
        case 'liquidity':
          final metrics = await _dashboardRepo.calculateAllMetrics(
            accountIds: accountIds,
          );
          final data = metrics.entries.map((e) => {
            return {
              'currency_code': e.key,
              'net_worth_cents': e.value.netWorthCents,
              'liquid_assets_cents': e.value.liquidAssetsCents,
              'safe_to_spend_cents': e.value.safeToSpendCents,
              'buying_power_cents': e.value.buyingPowerCents,
            };
          }).toList();
          return AIToolResult(
            success: true,
            content: jsonEncode({'metrics': data}),
          );

        default:
          return AIToolResult(
            success: false,
            content: jsonEncode({'error': 'query_type no reconocido: $queryType'}),
          );
      }
    } catch (e) {
      dev.log('FinancialSummaryTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error en consulta financiera: $e'}),
      );
    }
  }
}
```

- [ ] **Step 2: Create GoalTool**

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class GoalTool {
  final DatabaseHelper _db;
  final DashboardRepository _dashboardRepo;

  GoalTool({
    required DatabaseHelper db,
    required DashboardRepository dashboardRepo,
  }) : _db = db,
       _dashboardRepo = dashboardRepo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final goalId = args['goal_id'] as String?;
      final goalName = args['goal_name'] as String?;

      final db = await _db.database;
      List<Map<String, dynamic>> rows;

      if (goalId != null) {
        rows = await db.query(
          'goals',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [goalId],
          limit: 1,
        );
      } else if (goalName != null) {
        rows = await db.query(
          'goals',
          where: "name LIKE ? AND deleted_at IS NULL",
          whereArgs: ['%$goalName%'],
          limit: 1,
        );
      } else {
        return const AIToolResult(
          success: false,
          content: '{"error": "Se requiere goal_id o goal_name"}',
        );
      }

      if (rows.isEmpty) {
        return const AIToolResult(
          success: false,
          content: '{"error": "Meta no encontrada"}',
        );
      }

      final goal = GoalModel.fromMap(rows.first);

      // Calculate liquidity to determine progress
      final metrics = await _dashboardRepo.calculateAllMetrics();
      final currencyMetrics = metrics[goal.currencyCode];
      final liquidCents = currencyMetrics?.liquidAssetsCents ?? 0;

      return AIToolResult(
        success: true,
        content: jsonEncode({
          'name': goal.name,
          'target_amount_cents': goal.targetAmountCents,
          'currency_code': goal.currencyCode,
          'target_date': goal.targetDate,
          'liquid_assets_cents': liquidCents,
          'remaining_cents': goal.targetAmountCents - liquidCents,
        }),
      );
    } catch (e) {
      dev.log('GoalTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al consultar meta: $e'}),
      );
    }
  }
}
```

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/data/tools/financial_summary_tool.dart
git add frontend/lib/src/features/ai_assistant/data/tools/goal_tool.dart
git commit -m "feat(frontend): add financial summary and goal tool handlers"
```

---

## Task 11: Frontend — AIToolDispatcher

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/data/ai_tool_dispatcher.dart`

- [ ] **Step 1: Create dispatcher**

```dart
import 'dart:convert';

import 'package:pocket_pilot/src/features/ai_assistant/data/tools/financial_summary_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/goal_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/template_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/unsupported_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';

class AIToolDispatcher {
  final TransactionTool _transactionTool;
  final TemplateTool _templateTool;
  final FinancialSummaryTool _financialSummaryTool;
  final GoalTool _goalTool;
  final UnsupportedTool _unsupportedTool;

  AIToolDispatcher({
    required TransactionTool transactionTool,
    required TemplateTool templateTool,
    required FinancialSummaryTool financialSummaryTool,
    required GoalTool goalTool,
  }) : _transactionTool = transactionTool,
       _templateTool = templateTool,
       _financialSummaryTool = financialSummaryTool,
       _goalTool = goalTool,
       _unsupportedTool = UnsupportedTool();

  Future<AIToolResult> dispatch(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    switch (toolName) {
      case 'gestionar_transaccion':
        return _transactionTool.execute(arguments);
      case 'ejecutar_plantilla':
        return _templateTool.execute(arguments);
      case 'consultar_resumen_financiero':
        return _financialSummaryTool.execute(arguments);
      case 'gestionar_meta':
        return _goalTool.execute(arguments);
      case 'reportar_funcion_no_soportada':
        return _unsupportedTool.execute(arguments);
      default:
        return _unsupportedTool.execute({
          'user_intent': 'unknown tool: $toolName',
          'reason': 'Tool not registered in dispatcher',
        });
    }
  }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/data/ai_tool_dispatcher.dart
git commit -m "feat(frontend): add AIToolDispatcher with switch/case routing"
```

---

## Task 12: Frontend — Context Builder

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/data/ai_context_builder.dart`

- [ ] **Step 1: Create context builder**

```dart
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

class AIContextBuilder {
  final AccountLocalStore _accounts;
  final CategoryLocalStore _categories;
  final TransactionTemplateLocalStore _templates;
  final GoalLocalStore _goals;
  final UserPreferenceLocalStore _prefs;

  AIContextBuilder({
    required AccountLocalStore accounts,
    required CategoryLocalStore categories,
    required TransactionTemplateLocalStore templates,
    required GoalLocalStore goals,
    required UserPreferenceLocalStore prefs,
  }) : _accounts = accounts,
       _categories = categories,
       _templates = templates,
       _goals = goals,
       _prefs = prefs;

  Future<String> buildSystemPrompt() async {
    final lang = await _getLanguage();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final buf = StringBuffer();

    buf.writeln('Eres un asistente financiero personal. Responde siempre en $lang.');
    buf.writeln('Eres conciso y directo. Tus respuestas serán leídas en voz alta por TTS,');
    buf.writeln('así que usa oraciones cortas y naturales. No uses markdown, listas, ni formato.');
    buf.writeln('Usa las herramientas disponibles para ejecutar acciones. No inventes datos.');
    buf.writeln();
    buf.writeln('Hoy es: $dateStr');

    // Accounts
    final accounts = await _accounts.getAccounts();
    if (accounts.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Cuentas del usuario ==');
      for (final a in accounts) {
        buf.writeln('ID: ${a.id} | Nombre: ${a.name} | Tipo: ${a.type} | Moneda: ${a.currencyCode}');
      }
    }

    // Categories
    final categories = await _categories.getCategories();
    if (categories.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Categorías disponibles ==');
      for (final c in categories) {
        buf.writeln('ID: ${c.id} | Nombre: ${c.name} | Tipo: ${c.type}');
      }
    }

    // Templates
    final templateRows = await _templates.queryRows();
    if (templateRows.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Plantillas rápidas ==');
      for (final row in templateRows) {
        final t = TransactionTemplateModel.fromMap(row);
        final amountStr = t.amountCents != null
            ? '\$${(t.amountCents! / 100).toStringAsFixed(0)} ${t.currencyCode}'
            : 'monto variable';
        buf.writeln('ID: ${t.id} | Nombre: ${t.name} | Cuenta: ${t.accountId} | Monto: $amountStr');
      }
    }

    // Goals
    final goalRows = await _goals.queryRows();
    if (goalRows.isNotEmpty) {
      buf.writeln();
      buf.writeln('== Metas de ahorro ==');
      for (final row in goalRows) {
        final name = row['name'] as String;
        final target = row['target_amount_cents'] as int;
        final currency = row['currency_code'] as String;
        final targetDate = row['target_date'] as String?;
        buf.write('ID: ${row['id']} | Nombre: $name');
        buf.write(' | Objetivo: \$${(target / 100).toStringAsFixed(0)} $currency');
        if (targetDate != null) {
          buf.write(' | Fecha límite: $targetDate');
        }
        buf.writeln();
      }
    }

    return buf.toString();
  }

  Future<String> _getLanguage() async {
    final pref = await _prefs.getByKey('app.language');
    return pref?.prefValue ?? 'español';
  }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/data/ai_context_builder.dart
git commit -m "feat(frontend): add AIContextBuilder for dynamic system prompt"
```

---

## Task 13: Frontend — AISessionController

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/ui/ai_session_controller.dart`
- Modify: `frontend/pubspec.yaml` — add `speech_to_text` and `flutter_tts`

- [ ] **Step 1: Add dependencies to pubspec.yaml**

Add to the `dependencies:` section:

```yaml
  speech_to_text: ^7.0.0
  flutter_tts: ^4.2.0
```

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter pub get`

- [ ] **Step 2: Create AISessionController**

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:grpc/grpc.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:pocket_pilot/src/features/ai_assistant/data/ai_context_builder.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_tool_dispatcher.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_definitions.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart';

enum AISessionState { idle, listening, processing, speaking, error }

class AISessionController extends ChangeNotifier {
  final AIRemoteService _remote;
  final AIToolDispatcher _dispatcher;
  final AIContextBuilder _contextBuilder;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<AIMessage> _sessionMessages = [];
  final List<AIToolDefinition> _toolDefinitions = aiToolDefinitions;

  AISessionState _state = AISessionState.idle;
  AISessionState get state => _state;

  String _displayText = '';
  String get displayText => _displayText;

  int _toolCallCount = 0;
  static const _maxToolCalls = 10;

  AISessionController({
    required AIRemoteService remote,
    required AIToolDispatcher dispatcher,
    required AIContextBuilder contextBuilder,
  }) : _remote = remote,
       _dispatcher = dispatcher,
       _contextBuilder = contextBuilder {
    _tts.setCompletionHandler(_onSpeakingDone);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> startSession() async {
    if (_state != AISessionState.idle) return;

    _sessionMessages.clear();
    _toolCallCount = 0;

    try {
      final systemPrompt = await _contextBuilder.buildSystemPrompt();
      _sessionMessages.add(AIMessage(
        role: AIRole.AI_ROLE_SYSTEM,
        content: systemPrompt,
      ));

      final available = await _speech.initialize();
      if (!available) {
        _onError('El reconocimiento de voz no está disponible');
        return;
      }

      _startListening();
    } catch (e) {
      _onError('Error al iniciar sesión: $e');
    }
  }

  void endSession() {
    _speech.stop();
    _tts.stop();
    _sessionMessages.clear();
    _toolCallCount = 0;
    _state = AISessionState.idle;
    _displayText = '';
    notifyListeners();
  }

  // ── STT ─────────────────────────────────────────────────────────────────────

  void _startListening() {
    _state = AISessionState.listening;
    _displayText = 'Escuchando...';
    notifyListeners();

    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _onSpeechResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: 'es_MX',
    );

    // Timeout fallback
    Future.delayed(const Duration(seconds: 12), () {
      if (_state == AISessionState.listening) {
        _speech.stop();
        _onError('No escuché nada, intenta de nuevo más tarde');
      }
    });
  }

  void _onSpeechResult(String text) {
    if (text.trim().isEmpty) {
      _onError('No escuché nada, intenta de nuevo más tarde');
      return;
    }

    _sessionMessages.add(AIMessage(
      role: AIRole.AI_ROLE_USER,
      content: text,
    ));

    _state = AISessionState.processing;
    _displayText = 'Procesando...';
    notifyListeners();

    _sendToBackend();
  }

  // ── Backend Communication ───────────────────────────────────────────────────

  Future<void> _sendToBackend() async {
    try {
      final response = await _remote.chat(
        messages: _sessionMessages,
        tools: _toolDefinitions,
      );

      if (response.hasToolCall()) {
        _handleToolCall(response.toolCall);
      } else {
        _handleTextResponse(response.text);
      }
    } on GrpcError catch (e) {
      if (e.code == StatusCode.resourceExhausted) {
        _onError(e.message ?? 'Límite de uso alcanzado');
      } else if (e.code == StatusCode.unavailable) {
        _onError('No hay conexión a internet');
      } else {
        _onError('Error de conexión: ${e.message}');
      }
    } catch (e) {
      _onError('Ocurrió un error, intenta de nuevo más tarde');
    }
  }

  // ── Tool Call Handling ──────────────────────────────────────────────────────

  Future<void> _handleToolCall(AIToolCall toolCall) async {
    _sessionMessages.add(AIMessage(
      role: AIRole.AI_ROLE_ASSISTANT,
      toolCall: toolCall,
    ));

    try {
      final args = jsonDecode(toolCall.arguments) as Map<String, dynamic>;
      final result = await _dispatcher.dispatch(toolCall.name, args);

      _sessionMessages.add(AIMessage(
        role: AIRole.AI_ROLE_TOOL,
        toolCallId: toolCall.id,
        content: result.content,
      ));

      _toolCallCount++;

      if (_toolCallCount >= _maxToolCalls) {
        _sessionMessages.add(AIMessage(
          role: AIRole.AI_ROLE_USER,
          content: 'Por favor resume y responde con texto.',
        ));
      }

      await _sendToBackend();
    } catch (e) {
      // Send error as tool result so LLM can respond naturally
      _sessionMessages.add(AIMessage(
        role: AIRole.AI_ROLE_TOOL,
        toolCallId: toolCall.id,
        content: jsonEncode({'error': 'Error ejecutando herramienta: $e'}),
      ));
      await _sendToBackend();
    }
  }

  // ── Text Response / TTS ─────────────────────────────────────────────────────

  void _handleTextResponse(String text) {
    _sessionMessages.add(AIMessage(
      role: AIRole.AI_ROLE_ASSISTANT,
      content: text,
    ));

    _state = AISessionState.speaking;
    _displayText = text;
    notifyListeners();

    _tts.setLanguage('es-MX');
    _tts.speak(text);
  }

  void _onSpeakingDone() {
    if (_state != AISessionState.speaking) return;

    // If the LLM asked a question, listen again
    final lastAssistantMsg = _displayText;
    if (lastAssistantMsg.trimRight().endsWith('?')) {
      _startListening();
    } else {
      endSession();
    }
  }

  // ── Error Handling ──────────────────────────────────────────────────────────

  void _onError(String message) {
    _state = AISessionState.error;
    _displayText = message;
    notifyListeners();

    _tts.setLanguage('es-MX');
    _tts.speak(message);
    // _onSpeakingDone will be called by the TTS completion handler,
    // but for error state we want to end session after speaking
    _tts.setCompletionHandler(() {
      endSession();
      // Restore the normal handler
      _tts.setCompletionHandler(_onSpeakingDone);
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
```

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git add frontend/lib/src/features/ai_assistant/ui/ai_session_controller.dart
git commit -m "feat(frontend): add AISessionController with STT/LLM/TTS pipeline"
```

---

## Task 14: Frontend — AI Overlay Widget

**Files:**
- Create: `frontend/lib/src/features/ai_assistant/ui/ai_overlay.dart`

- [ ] **Step 1: Create overlay widget**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_session_controller.dart';

class AIOverlay extends StatelessWidget {
  const AIOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AISessionController>();
    if (controller.state == AISessionState.idle) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: controller.endSession,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {}, // Absorb tap to prevent closing
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStateIcon(controller.state),
                      const SizedBox(height: 16),
                      Text(
                        controller.displayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: controller.endSession,
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateIcon(AISessionState state) {
    switch (state) {
      case AISessionState.listening:
        return const _PulsingIcon(
          icon: Icons.mic,
          color: AppColors.primary,
        );
      case AISessionState.processing:
        return const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        );
      case AISessionState.speaking:
        return const _PulsingIcon(
          icon: Icons.volume_up,
          color: AppColors.primary,
        );
      case AISessionState.error:
        return const Icon(
          Icons.error_outline,
          color: AppColors.error,
          size: 48,
        );
      case AISessionState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (_controller.value * 0.5),
          child: Icon(
            widget.icon,
            color: widget.color,
            size: 48,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/src/features/ai_assistant/ui/ai_overlay.dart
git commit -m "feat(frontend): add AI overlay widget with state-based animations"
```

---

## Task 15: Frontend — DI Wiring in main.dart

**Files:**
- Modify: `frontend/lib/main.dart`

- [ ] **Step 1: Add AI assistant providers**

In `main.dart`, add the necessary imports at the top:

```dart
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_context_builder.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_tool_dispatcher.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/financial_summary_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/goal_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/template_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_overlay.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_session_controller.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
```

After the existing handler/service wiring and before the `MultiProvider`, create the AI dependencies:

```dart
// AI Assistant
final aiRemoteService = AIRemoteService();
final dashboardLocalStore = DashboardLocalStore(db: dbHelper);
final dashboardRepository = DashboardRepository(local: dashboardLocalStore);
final transactionLocalStore = TransactionLocalStore(db: dbHelper);
final transactionRepository = TransactionRepository(
  local: transactionLocalStore,
  outbox: syncOutbox,
);

final aiToolDispatcher = AIToolDispatcher(
  transactionTool: TransactionTool(repo: transactionRepository),
  templateTool: TemplateTool(
    db: dbHelper,
    transactionRepo: transactionRepository,
  ),
  financialSummaryTool: FinancialSummaryTool(
    dashboardRepo: dashboardRepository,
    dashboardLocal: dashboardLocalStore,
  ),
  goalTool: GoalTool(
    db: dbHelper,
    dashboardRepo: dashboardRepository,
  ),
);

final aiContextBuilder = AIContextBuilder(
  accounts: AccountLocalStore(db: dbHelper),
  categories: CategoryLocalStore(db: dbHelper),
  templates: TransactionTemplateLocalStore(db: dbHelper),
  goals: GoalLocalStore(db: dbHelper),
  prefs: UserPreferenceLocalStore(db: dbHelper),
);

final aiSessionController = AISessionController(
  remote: aiRemoteService,
  dispatcher: aiToolDispatcher,
  contextBuilder: aiContextBuilder,
);
```

Add to the existing `MultiProvider`'s `providers` list:

```dart
ChangeNotifierProvider<AISessionController>.value(value: aiSessionController),
```

Then wrap the `PocketPilotApp` widget (or its `MaterialApp` builder) to include the overlay. The simplest approach is to add a `Stack` in the app's main `Scaffold` or `MaterialApp.builder`:

In the `PocketPilotApp` or wherever the `MaterialApp` is defined, add a `builder` that overlays the AI widget:

```dart
MaterialApp.router(
  // ... existing config ...
  builder: (context, child) {
    return Stack(
      children: [
        child!,
        const AIOverlay(),
      ],
    );
  },
)
```

- [ ] **Step 2: Add a FAB or button to trigger the assistant**

In the main screen or scaffold that wraps all routes, add a floating action button or a persistent button. The simplest approach: add it to the `Stack` in the `MaterialApp.builder`:

```dart
builder: (context, child) {
  return Stack(
    children: [
      child!,
      const AIOverlay(),
      Positioned(
        right: 16,
        bottom: 80,
        child: _AILaunchButton(),
      ),
    ],
  );
},
```

Create a small helper widget (can be in `main.dart` or in the overlay file):

```dart
class _AILaunchButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AISessionController>();
    if (controller.state != AISessionState.idle) {
      return const SizedBox.shrink();
    }

    return FloatingActionButton(
      heroTag: 'ai_assistant',
      mini: true,
      backgroundColor: AppColors.primary,
      onPressed: controller.startSession,
      child: const Icon(Icons.mic, color: AppColors.backgroundDark),
    );
  }
}
```

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat(frontend): wire AI assistant DI and add overlay + FAB to main app"
```

---

## Task 16: Frontend — MethodChannel for OS Intent

**Files:**
- Modify: `frontend/lib/main.dart` (or `ai_session_controller.dart`)

- [ ] **Step 1: Add MethodChannel listener**

In `main.dart`, after creating `aiSessionController`, add the channel setup:

```dart
import 'package:flutter/services.dart';

// After aiSessionController creation:
const aiChannel = MethodChannel('com.pocketpilot/ai_assistant');
aiChannel.setMethodCallHandler((call) async {
  if (call.method == 'onLaunchAssistant') {
    aiSessionController.startSession();
  }
});
```

- [ ] **Step 2: Add app lifecycle observer**

Create a `WidgetsBindingObserver` to call `endSession()` when the app is backgrounded:

In the `PocketPilotApp` widget (or whatever `StatefulWidget` wraps the `MaterialApp`), add:

```dart
class _PocketPilotAppState extends State<PocketPilotApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      context.read<AISessionController>().endSession();
    }
  }

  // ... existing build method
}
```

If `PocketPilotApp` is currently a `StatelessWidget`, convert it to `StatefulWidget` to add the mixin.

- [ ] **Step 3: Verify build**

Run: `cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/main.dart
git commit -m "feat(frontend): add MethodChannel for OS intent and lifecycle observer"
```

---

## Task 17: Android — Intent Filter + App Shortcut

**Files:**
- Modify: `frontend/android/app/src/main/AndroidManifest.xml`
- Create: `frontend/android/app/src/main/res/xml/shortcuts.xml`

- [ ] **Step 1: Add intent filter to AndroidManifest.xml**

Inside the `<activity>` tag for `.MainActivity`, add an intent filter:

```xml
<intent-filter>
    <action android:name="com.pocketpilot.LAUNCH_ASSISTANT" />
    <category android:name="android.intent.category.DEFAULT" />
</intent-filter>

<meta-data
    android:name="android.app.shortcuts"
    android:resource="@xml/shortcuts" />
```

- [ ] **Step 2: Create shortcuts.xml**

Create `frontend/android/app/src/main/res/xml/shortcuts.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <shortcut
        android:shortcutId="launch_ai_assistant"
        android:enabled="true"
        android:shortcutShortLabel="@string/ai_shortcut_label"
        android:shortcutLongLabel="@string/ai_shortcut_long_label">
        <intent
            android:action="com.pocketpilot.LAUNCH_ASSISTANT"
            android:targetPackage="${applicationId}"
            android:targetClass="${applicationId}.MainActivity" />
    </shortcut>
</shortcuts>
```

- [ ] **Step 3: Add string resources**

Add to `frontend/android/app/src/main/res/values/strings.xml` (create if it doesn't exist):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="ai_shortcut_label">Asistente IA</string>
    <string name="ai_shortcut_long_label">Abrir asistente de voz</string>
</resources>
```

- [ ] **Step 4: Commit**

```bash
git add frontend/android/app/src/main/AndroidManifest.xml
git add frontend/android/app/src/main/res/xml/shortcuts.xml
git add frontend/android/app/src/main/res/values/strings.xml
git commit -m "feat(android): add intent filter and app shortcut for AI assistant"
```

---

## Task 18: iOS — Siri Shortcut (Basic)

**Files:**
- Modify: `frontend/ios/Runner/AppDelegate.swift`
- Modify: `frontend/ios/Runner/Info.plist`

- [ ] **Step 1: Add NSUserActivity to Info.plist**

Add to `Info.plist` inside the top-level `<dict>`:

```xml
<key>NSUserActivityTypes</key>
<array>
    <string>com.pocketpilot.launchAssistant</string>
</array>
```

- [ ] **Step 2: Handle activity in AppDelegate**

In `AppDelegate.swift`, add the method to forward the activity to Flutter:

```swift
override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    if userActivity.activityType == "com.pocketpilot.launchAssistant" {
        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: "com.pocketpilot/ai_assistant",
            binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("onLaunchAssistant", arguments: nil)
        return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/Runner/AppDelegate.swift
git add frontend/ios/Runner/Info.plist
git commit -m "feat(ios): add Siri Shortcut support for AI assistant"
```

---

## Task 19: Smoke Test — End-to-End Verification

- [ ] **Step 1: Run backend migration**

Apply the new migration to the development database:

```bash
psql $DATABASE_URL -f /Volumes/rusty-drive/projects/pocket-pilot/backend/migrations/002_ai_usage.sql
```

Expected: `CREATE TABLE` and `CREATE INDEX` success messages.

- [ ] **Step 2: Set environment variables and start backend**

```bash
export GEMINI_API_KEY="your-gemini-key-here"
export AI_DAILY_REQUEST_LIMIT=50
export AI_MONTHLY_TOKEN_LIMIT=500000
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go run ./cmd/server/main.go
```

Expected: `gRPC server listening on :50051`

- [ ] **Step 3: Test gRPC endpoint with grpcurl**

```bash
grpcurl -plaintext -d '{
  "messages": [
    {"role": 1, "content": "Eres un asistente financiero de prueba."},
    {"role": 2, "content": "Hola, ¿cómo estás?"}
  ],
  "tools": []
}' localhost:50051 pocket_pilot.v1.AIAssistantService/Chat
```

Expected: JSON response with `text` field containing a greeting from Gemini.

- [ ] **Step 4: Build and run Flutter app**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter run
```

Expected: App launches with the AI mic FAB visible. Tapping it starts listening.

- [ ] **Step 5: Full Flutter analysis**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze --no-fatal-infos
```

Expected: No errors.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete AI voice assistant integration"
```
