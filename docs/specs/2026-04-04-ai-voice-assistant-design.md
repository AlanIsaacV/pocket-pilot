# AI Voice Assistant — Design Spec

**Date:** 2026-04-04
**Status:** Draft

---

## 1. Overview

Voice-activated AI assistant for Pocket Pilot that reduces friction for common financial operations. The user speaks a command, Flutter captures it via STT, sends it to the backend (gRPC proxy → Gemini LLM with Function Calling), executes tool calls locally against SQLite, and reads the response via TTS.

**Core principle:** The backend is a stateless proxy. All business logic and tool execution happens in Flutter against the local SQLite database.

## 2. Architecture Summary

```
[User Voice] → STT → [Flutter: AISessionController]
    → gRPC Chat(messages + tools) → [Backend Proxy]
        → validates auth, checks rate limits
        → injects Gemini API key
        → translates to Gemini format → Gemini API
        → translates response back → AIChatResponse
    ← response (text | tool_call)

If tool_call:
    → [AIToolDispatcher] executes locally (SQLite)
    → appends tool result to session messages
    → loops back to gRPC Chat(...)

If text:
    → TTS reads response aloud
    → if question → listen again
    → if statement → close overlay
```

**Session model:** Ephemeral. The full message history lives in-memory (`List<AIMessage>`) on the Flutter side. No chat history is persisted to SQLite. Each voice session starts fresh.

**Loop model:** One tool call per turn. The LLM returns either text or a single tool call. Flutter executes, appends the result, and sends back the full history for the next turn. **Max 10 tool call turns per session** — if exceeded, the controller sends a final user message asking the LLM to summarize and respond with text, preventing degenerate loops.

**App lifecycle:** If the app is backgrounded mid-session, `endSession()` is called immediately. Sessions are ephemeral and not worth preserving across lifecycle events.

## 3. gRPC Contract

New file: `proto/pocket_pilot/v1/ai_assistant_service.proto`
Package: `pocket_pilot.v1`

### Service

```protobuf
service AIAssistantService {
  rpc Chat(AIChatRequest) returns (AIChatResponse);
}
```

### Messages

**AIChatRequest:**
- `repeated AIMessage messages` — full session history
- `repeated AIToolDefinition tools` — available tools

**AIMessage:**
- `AIRole role` — enum: `ROLE_SYSTEM`, `ROLE_USER`, `ROLE_ASSISTANT`, `ROLE_TOOL`
- `string content` — message text
- `optional string tool_call_id` — only when `role = ROLE_TOOL`, references the tool call being responded to
- `optional AIToolCall tool_call` — only when `role = ROLE_ASSISTANT` and the LLM requested a tool

**AIToolDefinition:**
- `string name` — e.g., `gestionar_transaccion`
- `string description` — description for the LLM
- `string parameters_schema` — JSON Schema as a JSON string. This is a deliberate deviation from the strongly-typed proto pattern used elsewhere: JSON Schema is inherently dynamic and cannot be reasonably represented as static proto messages. The Flutter side owns the schema definitions as Dart constants.

**AIChatResponse:**
- `oneof response`:
  - `string text` — text response for TTS
  - `AIToolCall tool_call` — LLM wants to execute a tool
- `AIUsageMetadata usage` — token consumption metadata

**AIToolCall:**
- `string id` — unique identifier for this call
- `string name` — tool name
- `string arguments` — JSON string of arguments

**AIUsageMetadata:**
- `int32 prompt_tokens`
- `int32 completion_tokens`
- `int32 total_tokens`

**AIRole enum:**
- `ROLE_UNSPECIFIED = 0`
- `ROLE_SYSTEM = 1`
- `ROLE_USER = 2`
- `ROLE_ASSISTANT = 3`
- `ROLE_TOOL = 4`

### Error Codes
- `RESOURCE_EXHAUSTED` — rate limit exceeded (daily requests or monthly tokens)
- `UNAVAILABLE` — LLM provider unreachable
- `INVALID_ARGUMENT` — malformed request

## 4. Backend — Proxy & Rate Limiting

### File Structure

```
backend/internal/ai_assistant/
├── handler.go        # Implements AIAssistantServiceServer
├── provider.go       # LLMProvider interface + GeminiProvider adapter
├── rate_limiter.go   # Rate limit check logic
└── repository.go     # PostgreSQL: usage tracking
```

### Handler Flow

1. Extract `user_id` from auth context (existing middleware)
2. `rateLimiter.Check(userId)` — returns `RESOURCE_EXHAUSTED` if exceeded
3. Translate `AIChatRequest` → Gemini format via `provider.Chat()`
4. Translate Gemini response → `AIChatResponse`
5. `repository.RecordUsage(userId, promptTokens, completionTokens)`
6. Return response

### LLM Provider Interface

```go
type LLMProvider interface {
    Chat(ctx context.Context, messages []AIMessage, tools []AIToolDefinition) (*LLMResponse, error)
}
```

`GeminiProvider` implements this interface:
- Model: `gemini-2.0-flash`
- Temperature: `0.1`
- Tool config: `function_calling_config.mode = AUTO`
- API key injected at initialization from server config

### Rate Limiting

Two configurable limits (env vars):
- `AI_DAILY_REQUEST_LIMIT` (default: 50) — requests per day per user
- `AI_MONTHLY_TOKEN_LIMIT` (default: 500,000) — total tokens per month per user

Whichever is hit first blocks the request with a descriptive error message.

### Database Migration

```sql
CREATE TABLE ai_usage (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    prompt_tokens INT NOT NULL,
    completion_tokens INT NOT NULL,
    total_tokens INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX idx_ai_usage_user_daily ON ai_usage (user_id, created_at);
```

Note: `updated_at` and `deleted_at` are included to comply with the project-wide PostgreSQL table convention, even though this table is append-only and backend-internal (no sync, no soft deletes in practice).

Repository queries:
- `CountRequestsToday(userId)` — `SELECT COUNT(*) WHERE user_id = ? AND created_at >= current_date`
- `SumTokensThisMonth(userId)` — `SELECT COALESCE(SUM(total_tokens), 0) WHERE user_id = ? AND created_at >= date_trunc('month', now())`
- `RecordUsage(userId, prompt, completion)` — INSERT

This table is backend-internal. It does not sync to Flutter and is not part of the outbox.

## 5. Frontend — Feature Structure

```
lib/src/features/ai_assistant/
├── domain/
│   ├── ai_tool_result.dart
│   └── ai_tool_name.dart
├── data/
│   ├── ai_remote_service.dart
│   ├── ai_tool_dispatcher.dart
│   ├── ai_context_builder.dart
│   └── tools/
│       ├── transaction_tool.dart
│       ├── template_tool.dart
│       ├── financial_summary_tool.dart
│       ├── goal_tool.dart
│       └── unsupported_tool.dart
└── ui/
    ├── ai_overlay.dart
    ├── ai_session_controller.dart
    └── ai_overlay_route_scope.dart
```

## 6. Frontend — AIToolDispatcher

### AIToolResult

```dart
class AIToolResult {
  final bool success;
  final String content; // JSON string sent to LLM as tool result
}
```

### AIToolDispatcher

- Constructor receives: `TransactionRepository`, `TransactionTemplateLocalStore`, `TransactionLocalStore`, `AccountLocalStore`, `CategoryLocalStore`, `GoalLocalStore`, `BudgetLocalStore`
- Method: `Future<AIToolResult> dispatch(String toolName, Map<String, dynamic> arguments)`
- Switch on `toolName` → delegates to specific tool class
- Unknown tool → `UnsupportedTool`

### Tool Implementations

**`TransactionTool`** (`gestionar_transaccion`) — Create only:
- Reads: `type` (income/expense/transfer), `account_id`, `amount_cents`, `currency_code`, `category_id`, `description`, `date`
- For transfers: also `to_account_id`
- Calls `TransactionRepository.createTransaction()` or `createTransfer()`
- Returns: `{"message": "Transacción creada", "id": "..."}`

**`TemplateTool`** (`ejecutar_plantilla`) — Execute template as transaction:
- Reads: `template_name`
- Queries `TransactionTemplateLocalStore` by name using case-insensitive `LIKE '%name%'` match
- If found: creates transaction with template values via `TransactionRepository`
- If not found: returns error with suggestions of similar template names

**`FinancialSummaryTool`** (`consultar_resumen_financiero`) — Read-only queries:
- Reads: `query_type` — one of: `account_balance`, `monthly_expenses`, `monthly_income`, `category_expenses`, `buying_power`, `liquidity`
- Executes local SQLite queries via corresponding LocalStores
- Returns formatted JSON with the requested data

**`GoalTool`** (`gestionar_meta`) — Read-only:
- Reads: `goal_name` or `goal_id`
- Queries `GoalLocalStore` for target and metadata
- Calculates progress using liquidity (same logic as dashboard)
- Returns goal status

**`UnsupportedTool`** (`reportar_funcion_no_soportada`) — Telemetry:
- Logs `toolName` + `arguments` locally
- Returns: `{"error": "Función no soportada"}`

## 7. Frontend — Context Builder (System Prompt)

### AIContextBuilder

- Constructor receives: `AccountLocalStore`, `CategoryLocalStore`, `TransactionTemplateLocalStore`, `GoalLocalStore`, `UserPreferenceLocalStore`
- Method: `Future<String> buildSystemPrompt()`
- Called once at session start. Result stored as first `AIMessage(role: ROLE_SYSTEM)`.

### System Prompt Structure

```
Eres un asistente financiero personal. Responde siempre en {idioma}.
Eres conciso y directo. Tus respuestas serán leídas en voz alta por TTS,
así que usa oraciones cortas y naturales. No uses markdown, listas, ni formato.
Usa las herramientas disponibles para ejecutar acciones. No inventes datos.

Hoy es: {fecha_actual}

== Cuentas del usuario ==
ID: abc123 | Nombre: Nómina BBVA | Tipo: bank | Moneda: MXN
ID: def456 | Nombre: Tarjeta Nu | Tipo: credit_card | Moneda: MXN

== Categorías disponibles ==
ID: cat01 | Nombre: Comida | Tipo: expense
ID: cat02 | Nombre: Transporte | Tipo: expense

== Plantillas rápidas ==
ID: tpl01 | Nombre: Netflix | Cuenta: Tarjeta Nu | Monto: $229 MXN | Categoría: Entretenimiento
ID: tpl02 | Nombre: Gasolina semanal | Cuenta: Nómina BBVA | Monto: $800 MXN | Categoría: Transporte

== Metas de ahorro ==
ID: goal01 | Nombre: Viaje a Europa | Objetivo: $50,000 MXN | Fecha límite: 2026-12-01
```

### Design Decisions
- **No balances in system prompt** — balances are queried on demand via `consultar_resumen_financiero` to avoid stale data
- **Templates include amount and category** — LLM needs these to execute without an extra query
- **Only active entities** — filtered by `deleted_at IS NULL`
- **Language from user preferences** — `app.language` key, default `es`
- **Plain text delimited by `==`** — token-light, easy for the LLM to parse

## 8. Frontend — Pipeline STT → LLM → TTS

### AISessionController (ChangeNotifier)

**State:**
```dart
enum AISessionState { idle, listening, processing, speaking, error }
```

**Dependencies (constructor):**
- `AIRemoteService`
- `AIToolDispatcher`
- `AIContextBuilder`
- `SpeechToText` (plugin)
- `FlutterTts` (plugin)

### Lifecycle

1. **`startSession()`** — User taps FAB or OS intent fires.
   - Calls `contextBuilder.buildSystemPrompt()` → stores as first message in `List<AIMessage> _sessionMessages`.
   - State → `listening`. Starts STT.

2. **`_onSpeechResult(String text)`** — STT delivers final text.
   - Appends `AIMessage(role: user, content: text)` to `_sessionMessages`.
   - State → `processing`. Calls `_sendToBackend()`.

3. **`_sendToBackend()`** — Sends to backend.
   - Calls `remoteService.chat(_sessionMessages, _toolDefinitions)`.
   - **If text response:**
     - Appends `AIMessage(role: assistant, content: text)` to `_sessionMessages`.
     - State → `speaking`. Plays TTS.
     - On TTS done → `_onSpeakingDone()`.
   - **If tool_call response:**
     - Appends `AIMessage(role: assistant, toolCall: toolCall)` to `_sessionMessages`.
     - Calls `dispatcher.dispatch(toolCall.name, jsonDecode(toolCall.arguments))`.
     - Appends `AIMessage(role: tool, toolCallId: toolCall.id, content: result.content)` to `_sessionMessages`.
     - Increments `_toolCallCount`. If `>= 10`, appends a user message "Please summarize and respond with text" and calls `_sendToBackend()` one final time.
     - Otherwise, calls `_sendToBackend()` again (next loop turn).

4. **`_onSpeakingDone()`** — TTS finished speaking.
   - If last LLM message ends with `?` → back to `listening`, start STT.
   - Otherwise → `endSession()`.

5. **`_onError(String errorMessage)`** — Any pipeline failure.
   - State → `error`.
   - TTS plays error message based on type.
   - On TTS done → `endSession()`.

6. **`endSession()`** — Clears `_sessionMessages`, state → `idle`, closes overlay.

### Error Handling

| Error | TTS Message | Action |
|-------|-------------|--------|
| STT timeout (~5s no result) | "No escuché nada, intenta de nuevo más tarde" | Close |
| No internet (gRPC `UNAVAILABLE`) | "No hay conexión a internet" | Close |
| Rate limit (gRPC `RESOURCE_EXHAUSTED`) | Backend message read aloud | Close |
| Tool dispatch failure | Error sent as tool result to LLM for natural response | Continue loop |
| Unknown error | "Ocurrió un error, intenta de nuevo más tarde" | Close |

## 9. Frontend — UI Overlay

### AIOverlay Widget

- `StatelessWidget` consuming `AISessionController` via `context.watch()`.
- Rendered as `OverlayEntry` over current screen (no navigation, no route push).
- Semi-transparent dark background. Content anchored to bottom of screen.

**States:**
| State | Visual |
|-------|--------|
| `listening` | Audio wave animation + "Escuchando..." |
| `processing` | Pulse/loading animation + "Procesando..." |
| `speaking` | Wave animation + LLM response text |
| `error` | Error icon + error text |

- Tap outside overlay → `endSession()` (cancels everything).

### AIOverlayRouteScope

- Not a GoRouter route. Mounted at the `MaterialApp` level (above the router) so the overlay is globally available regardless of current route. This deviates from the per-route RouteScope pattern because the assistant must be accessible from any screen.
- Creates `MultiProvider` with: `AIRemoteService`, `AIToolDispatcher`, `AIContextBuilder`, `AISessionController`.
- Reads required LocalStores and Repositories from the parent provider tree.

### OS Intent Activation

- **MethodChannel name:** `com.pocketpilot/ai_assistant`
- **Method:** `onLaunchAssistant` — triggers `AISessionController.startSession()`
- **Android:** Register an `Activity` intent filter for action `com.pocketpilot.LAUNCH_ASSISTANT`. The activity forwards the event to the MethodChannel and finishes. Exposed as an App Shortcut (static shortcut in `shortcuts.xml`).
- **iOS:** Register a Siri Shortcut with `NSUserActivity` type `com.pocketpilot.launchAssistant`. The `AppDelegate` forwards the activity to the MethodChannel.
- The intent only opens the overlay — it does not execute any action.

## 10. Tool Definitions (JSON Schema)

These are the `AIToolDefinition` objects sent in every request. The `parameters_schema` is a JSON Schema string.

### gestionar_transaccion
```json
{
  "name": "gestionar_transaccion",
  "description": "Crea una nueva transacción financiera (ingreso, gasto o transferencia entre cuentas).",
  "parameters_schema": {
    "type": "object",
    "properties": {
      "type": { "type": "string", "enum": ["income", "expense", "transfer_out"] },
      "account_id": { "type": "string", "description": "ID de la cuenta origen" },
      "to_account_id": { "type": "string", "description": "ID de la cuenta destino (solo para transferencias)" },
      "amount_cents": { "type": "integer", "description": "Monto en centavos" },
      "currency_code": { "type": "string", "description": "Código de moneda (ej: MXN)" },
      "category_id": { "type": "string", "description": "ID de la categoría (no aplica para transferencias)" },
      "description": { "type": "string" },
      "date": { "type": "string", "format": "date", "description": "Fecha en formato YYYY-MM-DD" }
    },
    "required": ["type", "account_id", "amount_cents", "currency_code", "date"]
  }
}
```

### ejecutar_plantilla
```json
{
  "name": "ejecutar_plantilla",
  "description": "Busca una plantilla de transacción por nombre y crea la transacción con los valores predefinidos.",
  "parameters_schema": {
    "type": "object",
    "properties": {
      "template_name": { "type": "string", "description": "Nombre de la plantilla a ejecutar" }
    },
    "required": ["template_name"]
  }
}
```

### consultar_resumen_financiero
```json
{
  "name": "consultar_resumen_financiero",
  "description": "Consulta datos financieros del usuario: saldos, gastos, ingresos, métricas del dashboard.",
  "parameters_schema": {
    "type": "object",
    "properties": {
      "query_type": {
        "type": "string",
        "enum": ["account_balance", "monthly_expenses", "monthly_income", "category_expenses", "buying_power", "liquidity"],
        "description": "Tipo de consulta financiera"
      },
      "account_id": { "type": "string", "description": "ID de cuenta (opcional, para filtrar)" },
      "category_id": { "type": "string", "description": "ID de categoría (opcional, para filtrar)" },
      "period": { "type": "string", "pattern": "^\\d{4}-\\d{2}$", "description": "Mes en formato YYYY-MM (default: mes actual)" }
    },
    "required": ["query_type"]
  }
}
```

### gestionar_meta
```json
{
  "name": "gestionar_meta",
  "description": "Consulta el estado de una meta de ahorro: progreso, monto faltante, fecha límite.",
  "parameters_schema": {
    "type": "object",
    "properties": {
      "goal_id": { "type": "string", "description": "ID de la meta" },
      "goal_name": { "type": "string", "description": "Nombre de la meta (alternativa al ID)" }
    },
    "anyOf": [
      { "required": ["goal_id"] },
      { "required": ["goal_name"] }
    ]
  }
}
```

### reportar_funcion_no_soportada
```json
{
  "name": "reportar_funcion_no_soportada",
  "description": "Usa esta herramienta cuando el usuario pida algo que no puedes hacer con las herramientas disponibles. Registra la intención para análisis futuro.",
  "parameters_schema": {
    "type": "object",
    "properties": {
      "user_intent": { "type": "string", "description": "Descripción de lo que el usuario intentó hacer" },
      "reason": { "type": "string", "description": "Por qué no se puede cumplir la solicitud" }
    },
    "required": ["user_intent", "reason"]
  }
}
```

## 11. Implementation Phases

### Phase 1: gRPC Contract (.proto)
- Define `ai_assistant_service.proto` with all messages and enums
- Run `make proto` to generate Go + Dart code

### Phase 2: Backend — Proxy + Rate Limiting
- Database migration for `ai_usage` table
- `repository.go` — usage tracking queries
- `rate_limiter.go` — check daily/monthly limits
- `provider.go` — `LLMProvider` interface + `GeminiProvider` adapter
- `handler.go` — wire it all together
- Register service in `cmd/server/main.go`

### Phase 3: Frontend — AIToolDispatcher
- Domain models (`AIToolResult`, `AIToolName`)
- `AIRemoteService` — gRPC stub wrapper
- Individual tool handlers (`transaction_tool.dart`, etc.)
- `AIToolDispatcher` — switch/dispatch

### Phase 4: Frontend — Context Builder
- `AIContextBuilder` — reads local data, formats system prompt

### Phase 5: Frontend — Pipeline + UI
- `AISessionController` — orchestrates STT → gRPC → tool dispatch → TTS
- `AIOverlay` widget
- `AIOverlayRouteScope` — DI setup
- FAB integration + MethodChannel for OS intent
- Error handling across the full pipeline
