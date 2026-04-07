package aiassistant

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"google.golang.org/genai"
)

// LLMProvider is the interface for any LLM backend.
type LLMProvider interface {
	Chat(ctx context.Context, messages []*AIMessageInput, tools []*AIToolInput) (*LLMResponse, error)
}

// AIMessageInput is the provider-agnostic input message.
type AIMessageInput struct {
	Role       string
	Content    string
	ToolCallID string       // only for role=tool
	ToolCall   *LLMToolCall // only for role=assistant with tool call
}

// AIToolInput is the provider-agnostic tool definition.
type AIToolInput struct {
	Name             string
	Description      string
	ParametersSchema string // JSON Schema string
}

const geminiModel = "gemini-3.1-flash-lite-preview"

type GeminiProvider struct {
	client *genai.Client
}

func NewGeminiProvider(apiKey string) *GeminiProvider {
	ctx := context.Background()
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  apiKey,
		Backend: genai.BackendGeminiAPI,
	})
	if err != nil {
		panic(fmt.Sprintf("genai.NewClient: %v", err))
	}
	return &GeminiProvider{client: client}
}

func (g *GeminiProvider) Chat(ctx context.Context, messages []*AIMessageInput, tools []*AIToolInput) (*LLMResponse, error) {
	contents, systemInstruction := g.buildContents(messages)

	config := &genai.GenerateContentConfig{
		Temperature: ptrFloat32(0.1),
	}

	if systemInstruction != nil {
		config.SystemInstruction = systemInstruction
	}

	if len(tools) > 0 {
		genaiTools, err := g.buildTools(tools)
		if err != nil {
			return nil, fmt.Errorf("gemini build tools: %w", err)
		}
		config.Tools = genaiTools
		config.ToolConfig = &genai.ToolConfig{
			FunctionCallingConfig: &genai.FunctionCallingConfig{
				Mode: genai.FunctionCallingConfigModeAuto,
			},
		}
	}

	resp, err := g.client.Models.GenerateContent(ctx, geminiModel, contents, config)
	if err != nil {
		log.Printf("[ERROR] Gemini GenerateContent error: %v", err)
		return nil, fmt.Errorf("gemini generate: %w", err)
	}

	return g.parseResponse(resp)
}

func (g *GeminiProvider) buildContents(messages []*AIMessageInput) ([]*genai.Content, *genai.Content) {
	var systemInstruction *genai.Content
	contents := make([]*genai.Content, 0, len(messages))
	toolNameByCallID := make(map[string]string)

	for _, msg := range messages {
		switch msg.Role {
		case "system":
			if strings.TrimSpace(msg.Content) != "" {
				systemInstruction = &genai.Content{
					Parts: []*genai.Part{genai.NewPartFromText(msg.Content)},
					Role:  "user",
				}
			}

		case "user":
			contents = append(contents, &genai.Content{
				Parts: []*genai.Part{genai.NewPartFromText(msg.Content)},
				Role:  "user",
			})

		case "assistant":
			if msg.ToolCall != nil {
				args := map[string]any{}
				if strings.TrimSpace(msg.ToolCall.Arguments) != "" {
					_ = json.Unmarshal([]byte(msg.ToolCall.Arguments), &args)
				}
				if msg.ToolCall.ID != "" {
					toolNameByCallID[msg.ToolCall.ID] = msg.ToolCall.Name
				}

				log.Printf("[DEBUG] buildContents assistant tool_call=%q thoughtSigLen=%d",
					msg.ToolCall.Name, len(msg.ToolCall.ThoughtSignature))

				// Attach thought signature directly to the function call part
				// (Gemini requires it on the functionCall part, not a separate thought part).
				fcPart := genai.NewPartFromFunctionCall(msg.ToolCall.Name, args)
				if len(msg.ToolCall.ThoughtSignature) > 0 {
					fcPart.ThoughtSignature = msg.ToolCall.ThoughtSignature
				}
				parts := []*genai.Part{fcPart}

				contents = append(contents, &genai.Content{
					Parts: parts,
					Role:  "model",
				})
			} else {
				contents = append(contents, &genai.Content{
					Parts: []*genai.Part{genai.NewPartFromText(msg.Content)},
					Role:  "model",
				})
			}

		case "tool":
			functionName := toolNameByCallID[msg.ToolCallID]
			if functionName == "" {
				functionName = msg.ToolCallID
			}
			if functionName == "" {
				functionName = "unknown_function"
			}

			responsePayload := map[string]any{"result": msg.Content}
			if strings.TrimSpace(msg.Content) != "" {
				var decoded any
				if err := json.Unmarshal([]byte(msg.Content), &decoded); err == nil {
					if m, ok := decoded.(map[string]any); ok {
						responsePayload = m
					} else {
						responsePayload = map[string]any{"result": decoded}
					}
				}
			}

			contents = append(contents, &genai.Content{
				Parts: []*genai.Part{genai.NewPartFromFunctionResponse(functionName, responsePayload)},
				Role:  "user",
			})
		}
	}

	return contents, systemInstruction
}

func (g *GeminiProvider) buildTools(tools []*AIToolInput) ([]*genai.Tool, error) {
	funcDecls := make([]*genai.FunctionDeclaration, 0, len(tools))
	for _, t := range tools {
		fd := &genai.FunctionDeclaration{
			Name:        t.Name,
			Description: t.Description,
		}

		if strings.TrimSpace(t.ParametersSchema) != "" {
			var schema genai.Schema
			if err := json.Unmarshal([]byte(t.ParametersSchema), &schema); err != nil {
				return nil, fmt.Errorf("invalid JSON schema for tool %q: %w", t.Name, err)
			}
			fd.Parameters = &schema
		}

		funcDecls = append(funcDecls, fd)
	}

	return []*genai.Tool{{FunctionDeclarations: funcDecls}}, nil
}

func (g *GeminiProvider) parseResponse(resp *genai.GenerateContentResponse) (*LLMResponse, error) {
	result := &LLMResponse{}

	if resp.UsageMetadata != nil {
		result.Usage = LLMUsage{
			PromptTokens:     int(resp.UsageMetadata.PromptTokenCount),
			CompletionTokens: int(resp.UsageMetadata.CandidatesTokenCount),
			TotalTokens:      int(resp.UsageMetadata.TotalTokenCount),
		}
	}

	parts := resp.Candidates[0].Content.Parts

	// Debug: log all parts from response
	for i, part := range parts {
		log.Printf("[DEBUG] parseResponse part[%d]: Thought=%v, ThoughtSigLen=%d, HasFunctionCall=%v, Text=%q",
			i, part.Thought, len(part.ThoughtSignature), part.FunctionCall != nil, part.Text)
	}

	// Extract thought signature (required for thinking models).
	// The signature may be on the function call part itself (Thought=false),
	// not only on dedicated thought parts.
	var thoughtSig []byte
	for _, part := range parts {
		if len(part.ThoughtSignature) > 0 {
			thoughtSig = part.ThoughtSignature
		}
	}
	log.Printf("[DEBUG] parseResponse: extracted thoughtSig len=%d", len(thoughtSig))

	functionCalls := resp.FunctionCalls()
	if len(functionCalls) > 0 {
		fc := functionCalls[0]
		argsJSON, err := json.Marshal(fc.Args)
		if err != nil {
			return nil, fmt.Errorf("gemini encode function args: %w", err)
		}
		result.ToolCall = &LLMToolCall{
			ID:               fmt.Sprintf("call_%s", fc.Name),
			Name:             fc.Name,
			Arguments:        string(argsJSON),
			ThoughtSignature: thoughtSig,
		}
		return result, nil
	}

	text := resp.Text()
	if strings.TrimSpace(text) == "" {
		return nil, fmt.Errorf("gemini: response has no text or tool call")
	}
	result.Text = text

	return result, nil
}

func ptrFloat32(v float32) *float32 { return &v }
