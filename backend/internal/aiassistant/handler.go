package aiassistant

import (
	"context"
	"log/slog"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"

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
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "request is required")
	}

	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	if err := h.rateLimiter.Check(ctx, userID); err != nil {
		if _, ok := status.FromError(err); ok {
			return nil, err
		}
		return nil, status.Errorf(codes.Internal, "rate limiter error: %v", err)
	}

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
				ID:               m.ToolCall.Id,
				Name:             m.ToolCall.Name,
				Arguments:        m.ToolCall.Arguments,
				ThoughtSignature: m.ToolCall.ThoughtSignature,
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

	llmResp, err := h.provider.Chat(ctx, messages, tools)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "llm error: %v", err)
	}

	if err := h.repo.RecordUsage(ctx, userID, FeatureChat, h.provider.Model(), llmResp.Usage.PromptTokens, llmResp.Usage.CompletionTokens); err != nil {
		slog.Error("aiassistant: failed to record usage", "user_id", userID, "error", err)
	}

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
				Id:               llmResp.ToolCall.ID,
				Name:             llmResp.ToolCall.Name,
				Arguments:        llmResp.ToolCall.Arguments,
				ThoughtSignature: llmResp.ToolCall.ThoughtSignature,
			},
		}
	} else {
		resp.Response = &pb.AIChatResponse_Text{Text: llmResp.Text}
	}

	return resp, nil
}

func (h *Handler) ReportUnsupportedTool(ctx context.Context, req *pb.ReportUnsupportedToolRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	if err := h.repo.RecordUnsupportedToolCall(ctx, userID, req.GetUserIntent(), req.GetReason()); err != nil {
		slog.Error("aiassistant: failed to record unsupported tool report", "error", err)
	}

	return &emptypb.Empty{}, nil
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
