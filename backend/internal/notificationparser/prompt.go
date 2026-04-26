package notificationparser

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/AlanIsaacV/pocket-pilot/internal/aiassistant"
)

// ParsedFromLLM es el resultado decodificado de la respuesta del LLM.
type ParsedFromLLM struct {
	Matched           bool    `json:"matched"`
	BankID            string  `json:"bank_id"`
	PatternID         string  `json:"pattern_id"`
	TransactionType   string  `json:"transaction_type"` // expense | income | transfer
	AmountCents       int64   `json:"amount_cents"`
	CurrencyCode      string  `json:"currency_code"`
	MerchantDesc      string  `json:"merchant_description"`
	CardLastDigits    string  `json:"card_last_digits"`
	ProposedRegex     string  `json:"proposed_regex"`
	Confidence        float64 `json:"confidence"`
}

// systemPrompt instruye al modelo. Crítico: ECMAScript named groups (Dart),
// JSON estricto, no incluir texto fuera del JSON. Few-shot con ejemplos
// reales BBVA — el LLM aprende del shape sin ver el regex final (lo
// proponemos nosotros vía la app cuando se valida con tests del engine).
const systemPrompt = `Eres un parser de notificaciones bancarias. Recibes una notificación push (package, title, text, big_text) y debes devolver SOLO un objeto JSON con la estructura indicada — sin markdown, sin texto adicional.

Si la notificación NO es transaccional (OTP, promoción, aviso, recordatorio, marketing), responde con {"matched": false}.

Si SÍ es una transacción, extrae los campos y propone un regex ECMAScript que matchearía notificaciones similares.

Schema de salida (JSON ESTRICTO):
{
  "matched": true | false,
  "bank_id": string,             // ej. "bbva_mx" o "unknown" si no lo identificas
  "pattern_id": string,           // snake_case describiendo el patrón, ej. "purchase_card_v3"
  "transaction_type": "expense" | "income" | "transfer",
  "amount_cents": int,            // monto en centavos (ej. $1,234.56 -> 123456)
  "currency_code": "MXN" | "USD" | ...,
  "merchant_description": string, // limpio, sin metadatos extra
  "card_last_digits": string,     // "" si no aparece
  "proposed_regex": string,       // ECMAScript con named groups (?<amount>...)(?<merchant>...) etc.
  "confidence": float             // 0..1
}

REGLAS para proposed_regex:
- USAR named groups ECMAScript (?<name>...)  — NUNCA Python (?P<name>...).
- NO usar backreferences (\1, \2, ...).
- NO usar quantifiers anidados peligrosos como (.+)+, (.*)*.
- Mantenerlo bajo 200 caracteres.
- Los nombres de captura esperados son: amount, currency, merchant, digits.

Ejemplo 1 (BBVA MX, compra con tarjeta):
input:
  package: com.bbva.bancomermovil
  title:   BBVA México
  text:    Cargo aprobado por $1,234.56 MXN en STARBUCKS REFORMA, con tarjeta term. 1234.
output:
  {"matched": true, "bank_id": "bbva_mx", "pattern_id": "purchase_card",
   "transaction_type": "expense", "amount_cents": 123456, "currency_code": "MXN",
   "merchant_description": "STARBUCKS REFORMA", "card_last_digits": "1234",
   "proposed_regex": "Cargo\\s+aprobado\\s+por\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+en\\s+(?<merchant>.+?),\\s+con\\s+tarjeta\\s+term\\.\\s*(?<digits>\\d{4})",
   "confidence": 0.95}

Ejemplo 2 (BBVA MX, OTP — NO es transacción):
input:
  package: com.bbva.bancomermovil
  title:   BBVA México
  text:    Tu código dinámico es 837492. No lo compartas.
output:
  {"matched": false}

Ejemplo 3 (BBVA MX, depósito recibido):
input:
  package: com.bbva.bancomermovil
  title:   BBVA México
  text:    Recibiste $5,000.00 MXN de Juan Pérez. Concepto: Pago.
output:
  {"matched": true, "bank_id": "bbva_mx", "pattern_id": "transfer_in",
   "transaction_type": "income", "amount_cents": 500000, "currency_code": "MXN",
   "merchant_description": "Juan Pérez", "card_last_digits": "",
   "proposed_regex": "Recibiste\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+de\\s+(?<merchant>[^.\\n]+)",
   "confidence": 0.92}`

// BuildMessages construye los mensajes para LLMProvider.Chat.
func BuildMessages(packageName, title, text, bigText string) []*aiassistant.AIMessageInput {
	user := fmt.Sprintf(
		"input:\n  package: %s\n  title:   %s\n  text:    %s\n  big_text: %s\noutput:",
		packageName, title, text, bigText,
	)
	return []*aiassistant.AIMessageInput{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: user},
	}
}

// ParseLLMResponse decodifica la respuesta del LLM. Tolera fences markdown
// (```json ... ```) que el modelo a veces agrega a pesar del prompt; los
// quita antes del Unmarshal. Devuelve error si la respuesta no es JSON
// válido o si campos críticos están fuera de rango.
func ParseLLMResponse(raw string) (*ParsedFromLLM, error) {
	body := stripJSONFences(strings.TrimSpace(raw))
	if body == "" {
		return nil, errors.New("llm response is empty")
	}

	var out ParsedFromLLM
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		return nil, fmt.Errorf("llm response is not valid JSON: %w", err)
	}

	if !out.Matched {
		return &out, nil
	}

	if out.AmountCents <= 0 {
		return nil, fmt.Errorf("llm response has invalid amount_cents: %d", out.AmountCents)
	}
	switch out.TransactionType {
	case "expense", "income", "transfer":
	default:
		return nil, fmt.Errorf("llm response has invalid transaction_type: %q", out.TransactionType)
	}
	if out.Confidence < 0 || out.Confidence > 1 {
		out.Confidence = 0
	}
	return &out, nil
}

// stripJSONFences quita bloques de markdown ```json ... ``` que algunos
// modelos insisten en agregar. Si no hay fences, devuelve la string tal cual.
func stripJSONFences(s string) string {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "```") {
		return s
	}
	// quitar primera línea (```json o ```)
	if i := strings.Index(s, "\n"); i >= 0 {
		s = s[i+1:]
	}
	// quitar el cierre ```
	if i := strings.LastIndex(s, "```"); i >= 0 {
		s = s[:i]
	}
	return strings.TrimSpace(s)
}
