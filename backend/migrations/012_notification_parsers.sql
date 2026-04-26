-- notification_parsers: catálogo global de parsers de notificaciones bancarias.
-- Tabla compartida entre todos los usuarios (sin user_id), accesible solo en
-- modo pull. La app cliente reemplaza su definición local cuando llega una
-- versión más nueva — esto permite shipear nuevos regex sin redeploy.
--
-- definition: JSON con la forma de NotificationParserDefinition del frontend
-- (schema_version, bank_id, package_names, version, ignore_patterns, patterns,
-- captures, transforms whitelisted en código, etc.).
--
-- bank_id es el natural key. version es el contador del parser; el cliente
-- compara contra la versión local y decide si reemplaza.

CREATE TABLE notification_parsers (
    id          uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    bank_id     TEXT         NOT NULL UNIQUE,
    version     INT          NOT NULL,
    definition  JSONB        NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  timestamptz  NOT NULL DEFAULT NOW(),
    updated_at  timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz,

    CONSTRAINT notification_parsers_version_positive
        CHECK (version > 0)
);

CREATE INDEX idx_notification_parsers_updated_at
    ON notification_parsers (updated_at);

CREATE INDEX idx_notification_parsers_active
    ON notification_parsers (bank_id)
    WHERE is_active = TRUE AND deleted_at IS NULL;

CREATE TRIGGER set_updated_at_notification_parsers
    BEFORE UPDATE
    ON notification_parsers
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

-- Seed: BBVA México v1. Espejo del asset frontend/assets/parsers/bbva_mx.json
-- al momento de Fase 3. Los siguientes ajustes se hacen con UPDATE + version++,
-- sin tocar este archivo.
INSERT INTO notification_parsers (bank_id, version, definition) VALUES (
    'bbva_mx',
    1,
    $bbva$
{
  "schema_version": 1,
  "bank_id": "bbva_mx",
  "display_name": "BBVA México",
  "package_names": [
    "com.bbva.bancomermovil",
    "com.bancomer.mbanking"
  ],
  "version": 1,
  "default_currency": "MXN",
  "ignore_patterns": [
    {
      "field": "title",
      "regex": "(?i)(promoci[oó]n|aviso|publicidad|recordatorio|oferta)"
    },
    {
      "field": "text",
      "regex": "(?i)(token|c[oó]digo de seguridad|c[oó]digo din[aá]mico|sms din[aá]mico|verificaci[oó]n)"
    }
  ],
  "patterns": [
    {
      "id": "purchase_card",
      "transaction_type": "expense",
      "match": {
        "field": "text",
        "regex": "(?:Cargo|Compra)\\s+(?:aprobad[ao]|realizad[ao])(?:\\s+(?:por|de))?\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+en\\s+(?<merchant>.+?)(?:,|\\.|\\s+con\\s+).*?(?:tarjeta|term\\.?)\\s*(?:term\\.?\\s*)?(?<digits>\\d{4})",
        "flags": "is"
      },
      "captures": {
        "amount_cents": {"from": "amount", "transform": "money_to_cents"},
        "currency_code": {"from": "currency", "transform": "upper", "default": "MXN"},
        "merchant_description": {"from": "merchant", "transform": "trim"},
        "card_last_digits": {"from": "digits"}
      }
    },
    {
      "id": "online_purchase",
      "transaction_type": "expense",
      "match": {
        "field": "text",
        "regex": "Compra\\s+en\\s+l[ií]nea(?:\\s+por)?\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+en\\s+(?<merchant>[^.,\\n]+(?:\\.[^.,\\n\\s]+)*)",
        "flags": "is"
      },
      "captures": {
        "amount_cents": {"from": "amount", "transform": "money_to_cents"},
        "currency_code": {"from": "currency", "transform": "upper", "default": "MXN"},
        "merchant_description": {"from": "merchant", "transform": "trim"}
      }
    },
    {
      "id": "transfer_in",
      "transaction_type": "income",
      "match": {
        "field": "text",
        "regex": "(?:Recibiste|Te depositaron)\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+(?:de|por)\\s+(?<sender>[^.\\n]+?)(?:\\.|$|\\s+Concepto[:.])",
        "flags": "is"
      },
      "captures": {
        "amount_cents": {"from": "amount", "transform": "money_to_cents"},
        "currency_code": {"from": "currency", "transform": "upper", "default": "MXN"},
        "merchant_description": {"from": "sender", "transform": "trim"}
      }
    },
    {
      "id": "atm_withdrawal",
      "transaction_type": "expense",
      "match": {
        "field": "text",
        "regex": "Retiro(?:\\s+en\\s+cajero)?\\s+por\\s+\\$(?<amount>[\\d,]+\\.\\d{2})\\s*(?<currency>[A-Z]{3})?\\s+(?:en\\s+(?<location>.+?))?(?:,|\\.|\\s+con\\s+).*?(?:tarjeta|term\\.?)\\s*(?:term\\.?\\s*)?(?<digits>\\d{4})",
        "flags": "is"
      },
      "captures": {
        "amount_cents": {"from": "amount", "transform": "money_to_cents"},
        "currency_code": {"from": "currency", "transform": "upper", "default": "MXN"},
        "merchant_description": {"from": "location", "transform": "trim", "default": "Retiro ATM"},
        "card_last_digits": {"from": "digits"}
      }
    }
  ]
}
    $bbva$::jsonb
);
