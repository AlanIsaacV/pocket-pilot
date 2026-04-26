package notificationparser

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
	pb "github.com/AlanIsaacV/pocket-pilot/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1"
	"github.com/AlanIsaacV/pocket-pilot/internal/middleware"
)

// LLMFallback agrupa las dependencias del path Fase 4: el provider del LLM,
// el rate limiter (con feature='notification_parser'), el repo de uso para
// registrar tokens, y el repo de candidatos para persistir samples cuando el
// usuario optó por "ayudar a mejorar la app". Su lifecycle se resuelve en
// cmd/server/main.go.
type LLMFallback struct {
	llm           aiassistant.LLMProvider
	limiter       *aiassistant.RateLimiter
	usageRepo     *aiassistant.Repository
	candidateRepo *CandidateRepository
	modelVersion  string // para etiquetar candidate_parsers.llm_model_version
}

func NewLLMFallback(
	llm aiassistant.LLMProvider,
	limiter *aiassistant.RateLimiter,
	usageRepo *aiassistant.Repository,
	candidateRepo *CandidateRepository,
	modelVersion string,
) *LLMFallback {
	return &LLMFallback{
		llm:           llm,
		limiter:       limiter,
		usageRepo:     usageRepo,
		candidateRepo: candidateRepo,
		modelVersion:  modelVersion,
	}
}

// ParseNotification implementa el RPC del proto. La autenticación corre en el
// interceptor; aquí asumimos userID disponible.
func (h *Handler) ParseNotification(ctx context.Context, req *pb.ParseNotificationRequest) (*pb.ParseNotificationResponse, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "request is required")
	}
	if h.llmFallback == nil {
		return nil, status.Error(codes.Unimplemented, "LLM fallback not configured on this server")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	// Validación mínima de input antes de gastar cuota.
	if req.PackageName == "" {
		return nil, status.Error(codes.InvalidArgument, "package_name is required")
	}
	if req.Title == "" && req.Text == "" && req.BigText == "" {
		return nil, status.Error(codes.InvalidArgument, "at least one of title/text/big_text must be set")
	}

	// Rate limit antes de invocar al LLM (no quemamos cuota si ya excedió).
	if err := h.llmFallback.limiter.Check(ctx, userID); err != nil {
		if _, ok := status.FromError(err); ok {
			return nil, err
		}
		return nil, status.Errorf(codes.Internal, "rate limiter error: %v", err)
	}

	// Invocar LLM.
	messages := BuildMessages(req.PackageName, req.Title, req.Text, req.BigText)
	llmResp, err := h.llmFallback.llm.Chat(ctx, messages, nil)
	if err != nil {
		slog.Error("notificationparser: llm Chat failed", "user_id", userID, "error", err)
		return nil, status.Errorf(codes.Internal, "llm error: %v", err)
	}

	// Registrar uso ANTES de parsear — la cuota debe contabilizarse incluso
	// si el LLM devolvió texto inválido (gastó tokens igual).
	if err := h.llmFallback.usageRepo.RecordUsage(
		ctx, userID, aiassistant.FeatureNotificationParser,
		llmResp.Usage.PromptTokens, llmResp.Usage.CompletionTokens,
	); err != nil {
		slog.Error("notificationparser: failed to record usage", "user_id", userID, "error", err)
	}

	// Parsear JSON estricto.
	parsed, err := ParseLLMResponse(llmResp.Text)
	if err != nil {
		slog.Warn("notificationparser: llm response failed schema validation",
			"user_id", userID, "raw_len", len(llmResp.Text), "error", err)
		// Tratamos respuesta inválida como "no match" para no romper al
		// cliente; la noti queda unparseable.
		return &pb.ParseNotificationResponse{Matched: false}, nil
	}

	if !parsed.Matched {
		return &pb.ParseNotificationResponse{Matched: false}, nil
	}

	// Validar regex propuesto. Si falla, descartamos solo el regex; la
	// extracción sigue siendo válida.
	validatedRegex := parsed.ProposedRegex
	if validatedRegex != "" {
		if err := ValidateRegex(validatedRegex); err != nil {
			slog.Info("notificationparser: rejecting proposed regex",
				"reason", err, "len", len(validatedRegex))
			validatedRegex = ""
		}
	}

	// Persistir candidate solo si el usuario lo autorizó (toggle help_improve_app).
	if req.HelpImproveApp {
		fields := map[string]any{
			"amount_cents":         parsed.AmountCents,
			"currency_code":        parsed.CurrencyCode,
			"merchant_description": parsed.MerchantDesc,
			"card_last_digits":     parsed.CardLastDigits,
			"transaction_type":     parsed.TransactionType,
		}
		fieldsJSON, err := json.Marshal(fields)
		if err != nil {
			slog.Error("notificationparser: marshal extracted_fields failed", "error", err)
		} else {
			bankID := parsed.BankID
			if bankID == "" {
				bankID = "unknown"
			}
			_, insErr := h.llmFallback.candidateRepo.Insert(ctx, CandidateParser{
				BankID:            bankID,
				PackageName:       req.PackageName,
				SampleTitle:       req.Title,
				SampleText:        req.Text,
				SampleBigText:     req.BigText,
				ProposedPatternID: parsed.PatternID,
				ProposedRegex:     validatedRegex,
				ProposedTxType:    parsed.TransactionType,
				ProposedCurrency:  parsed.CurrencyCode,
				ExtractedFields:   fieldsJSON,
				LLMProvider:       "gemini",
				LLMModelVersion:   h.llmFallback.modelVersion,
				LLMConfidence:     parsed.Confidence,
			})
			if insErr != nil {
				// No bloquea la respuesta al usuario — solo telemetría.
				slog.Error("notificationparser: insert candidate failed", "error", insErr)
			}
		}
	}

	return &pb.ParseNotificationResponse{
		Matched:             true,
		AmountCents:         parsed.AmountCents,
		CurrencyCode:        parsed.CurrencyCode,
		MerchantDescription: parsed.MerchantDesc,
		CardLastDigits:      parsed.CardLastDigits,
		TransactionType:     parsed.TransactionType,
		ProposedPatternId:   parsed.PatternID,
	}, nil
}

// ensure compile-time unused-import check happens correctly
var _ = errors.New
