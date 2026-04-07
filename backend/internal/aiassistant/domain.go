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
	ID               string
	Name             string
	Arguments        string // JSON string
	ThoughtSignature []byte // opaque signature for thinking models
}

type LLMUsage struct {
	PromptTokens     int
	CompletionTokens int
	TotalTokens      int
}
