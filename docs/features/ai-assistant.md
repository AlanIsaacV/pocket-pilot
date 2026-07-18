# AI Assistant Architecture

Módulo `backend/internal/aiassistant/` — encapsula el provider Gemini y la
lógica de cuotas (RateLimiter) compartida por todo feature que invoque al
LLM en el backend. Hoy hay dos consumidores: el chat del AI Assistant
(`Chat` RPC) y el LLM fallback de notification_capture
(`ParseNotification`, ver `architecture/notification_capture.md`).

## Responsabilidades

- **`LLMProvider`** (interfaz) — abstracción provider-agnóstica con dos
  métodos: `Chat(ctx, messages, tools)` y `Model() string`. La
  implementación concreta `GeminiProvider` envuelve el SDK
  `google.golang.org/genai`.
- **`Repository`** — persistencia de uso en `ai_usage` (tokens por
  request, segmentado por `feature` y `model`).
- **`RateLimiter`** — un instance por feature, con cuota diaria
  (requests/día) y mensual (tokens/mes) propias. Filtra `ai_usage` por
  `feature` para que features no se canibalicen mutuamente.
- **`Handler`** — implementa el RPC `Chat` del proto AI Assistant.

Los demás módulos (p.ej. `notificationparser`) consumen `LLMProvider` y
`RateLimiter` por inyección de dependencia desde `cmd/server/main.go`.

## Features

| Feature key | Constante | Consumidor | Quota daily env | Quota monthly env | Modelo env | Default modelo |
|-------------|-----------|------------|-----------------|-------------------|------------|----------------|
| `chat`      | `aiassistant.FeatureChat` | `aiassistant.Handler.Chat` (RPC) | `AI_DAILY_REQUEST_LIMIT` (50) | `AI_MONTHLY_TOKEN_LIMIT` (500_000) | `AI_CHAT_MODEL` | `gemini-3.1-flash-lite-preview` |
| `notification_parser` | `aiassistant.FeatureNotificationParser` | `notificationparser.LLMFallback.ParseNotification` | `NOTIFICATION_PARSER_DAILY_LIMIT` (50) | `NOTIFICATION_PARSER_MONTHLY_TOKEN_LIMIT` (200_000) | `NOTIFICATION_PARSER_MODEL` | `gemini-3.1-flash-lite-preview` |

Las constantes están en `aiassistant/repository.go`. Si se agrega un
feature, declarar también ahí; el ENUM no existe en DB (es `TEXT`) pero
el código es la single source of truth.

## Modelo por feature

Cada `GeminiProvider` se construye con un modelo concreto (string que
acepte el SDK Gemini, p.ej. `gemini-3.1-flash`, `gemini-3.1-pro`,
`gemini-3.1-flash-lite-preview`). El nombre vive en el provider y se
expone via `Model()`; los handlers lo leen para etiquetar
`ai_usage.model` y, en notification_parser, también
`candidate_parsers.llm_model_version`. **No hay strings duplicados** —
quien quiera saber qué modelo se usó en una llamada lo lee del provider
o de la columna persistida.

Wiring (en `cmd/server/main.go`):

```go
chatProvider   := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey, cfg.AIChatModel)
parserProvider := aiassistant.NewGeminiProvider(cfg.GeminiAPIKey, cfg.NotificationParserModel)
```

Compartir el `genai.Client` entre dos providers no aporta hoy (el cliente
es ligero y stateless tras setup); si se vuelve un costo medible,
refactorizar a un único `genai.Client` inyectado.

## Persistencia: `ai_usage`

Schema vivo (post mig 017):

```sql
CREATE TABLE ai_usage (
    id                 uuid PRIMARY KEY,
    user_id            uuid NOT NULL,
    feature            TEXT NOT NULL DEFAULT 'chat',     -- mig 013
    model              TEXT NOT NULL DEFAULT 'gemini-3.1-flash-lite-preview', -- mig 017
    prompt_tokens      INT  NOT NULL,
    completion_tokens  INT  NOT NULL,
    total_tokens       INT  NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT NOW(),
    updated_at         timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_usage_user_feature_created ON ai_usage (user_id, feature, created_at);
CREATE INDEX idx_ai_usage_model_created        ON ai_usage (model, created_at);
```

`feature` y `model` son dimensiones independientes: `feature` segmenta la
**cuota** (cada `RateLimiter` filtra por su feature); `model` segmenta
el **costo** (cada modelo Gemini tiene tarifa distinta). Los dos defaults
backfillan filas históricas con su única realidad documental.

### Queries operativas

Gasto del mes por feature:

```sql
SELECT feature, SUM(total_tokens) AS tokens
FROM ai_usage
WHERE created_at >= date_trunc('month', NOW())
GROUP BY feature;
```

Gasto del mes por modelo (input para análisis de costo):

```sql
SELECT model, SUM(prompt_tokens) AS in_tok, SUM(completion_tokens) AS out_tok
FROM ai_usage
WHERE created_at >= date_trunc('month', NOW())
GROUP BY model;
```

Breakdown feature × modelo (ver qué feature está consumiendo el modelo
caro):

```sql
SELECT feature, model, COUNT(*) AS reqs, SUM(total_tokens) AS tokens
FROM ai_usage
WHERE created_at >= NOW() - interval '7 days'
GROUP BY feature, model
ORDER BY tokens DESC;
```

## Cómo agregar un feature nuevo

1. Declarar la constante en `aiassistant/repository.go` (`FeatureXxx = "xxx"`).
2. En `cmd/server/main.go`:
   - Construir un `GeminiProvider` con su modelo (env var nueva si lo
     amerita; reusa uno existente si comparte modelo).
   - Construir un `RateLimiter` con `feature=FeatureXxx` y sus límites.
3. Inyectar el provider y el limiter en el handler del feature.
4. El handler llama `provider.Chat(...)`, luego
   `repo.RecordUsage(ctx, userID, FeatureXxx, provider.Model(), prompt, completion)`.
5. (Opcional) Agregar índice si hay queries operativas frecuentes.

## Tests relevantes

- `internal/aiassistant/rate_limiter_test.go` — integration test que
  valida aislamiento de cuotas entre features (skip sin
  `TEST_DATABASE_URL`).

## Referencias cruzadas

- `architecture/notification_capture.md` — descripción del consumidor
  `notification_parser` (Fase 4 LLM fallback).
- `backend/migrations/013_ai_usage_feature.sql` — añade `feature`.
- `backend/migrations/017_ai_usage_model.sql` — añade `model`.
