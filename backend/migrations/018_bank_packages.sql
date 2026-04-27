-- Fase 8: package selection dinámica + loop comunitario.
--
-- Tres tablas nuevas que reemplazan la allowlist hardcoded del NLS Kotlin:
--
--   bank_packages       global pull-only, mismo patrón que notification_parsers.
--                       package_name → bank_id. El admin promueve entradas
--                       desde package_suggestions vía SQL directo o, a futuro,
--                       admin path.
--
--   bank_aliases        user-scoped sync (push+pull, LWW), mismo patrón que
--                       account_card_mappings. La decisión per-user de "este
--                       package es mi banco con esta etiqueta". Sincroniza
--                       entre devices del mismo usuario; la decisión de
--                       capturar localmente vive en watched_packages (tabla
--                       FE-only, no entra a este migration).
--
--   package_suggestions anónimo (sin user_id), mismo patrón que
--                       candidate_parsers. Se pobla cuando el usuario marca
--                       un package como banco en su pantalla "Mis bancos" y
--                       tiene help_improve_app=ON. El admin revisa y decide
--                       si promueve a bank_packages.

-- ── bank_packages (catálogo global) ──────────────────────────────────────────
CREATE TABLE bank_packages (
    id            uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    package_name  TEXT         NOT NULL UNIQUE,
    bank_id       TEXT         NOT NULL,
    default_label TEXT         NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    timestamptz  NOT NULL DEFAULT NOW(),
    updated_at    timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at    timestamptz
);

CREATE INDEX idx_bank_packages_updated_at
    ON bank_packages (updated_at);

CREATE INDEX idx_bank_packages_active
    ON bank_packages (bank_id)
    WHERE is_active = TRUE AND deleted_at IS NULL;

CREATE TRIGGER set_updated_at_bank_packages
    BEFORE UPDATE
    ON bank_packages
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

-- Seed: BBVA México. Espejo de la allowlist hardcoded que vivía en
-- BankNotificationListenerService.kt antes de Fase 8.
INSERT INTO bank_packages (package_name, bank_id, default_label) VALUES
    ('com.bbva.bancomermovil', 'bbva_mx', 'BBVA'),
    ('com.bancomer.mbanking',  'bbva_mx', 'BBVA');

-- ── bank_aliases (user-scoped sync) ──────────────────────────────────────────
CREATE TABLE bank_aliases (
    id              uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    user_id         uuid         NOT NULL REFERENCES users (id),
    package_name    TEXT         NOT NULL,
    bank_id         TEXT,
    display_label   TEXT         NOT NULL,
    created_at      timestamptz  NOT NULL DEFAULT NOW(),
    updated_at      timestamptz  NOT NULL DEFAULT NOW(),
    deleted_at      timestamptz,

    -- Un usuario solo puede tener un alias activo por package. Si re-marca
    -- (deleted_at no nulo y vuelve a marcar), el cliente reusa el mismo id
    -- y reactiva la fila vía LWW (mismo patrón que cardmapping).
    CONSTRAINT bank_aliases_user_package_unique
        UNIQUE (user_id, package_name)
);

CREATE INDEX idx_bank_aliases_user_updated_at
    ON bank_aliases (user_id, updated_at);

CREATE INDEX idx_bank_aliases_lookup
    ON bank_aliases (user_id, package_name)
    WHERE deleted_at IS NULL;

CREATE TRIGGER set_updated_at_bank_aliases
    BEFORE UPDATE
    ON bank_aliases
    FOR EACH ROW
EXECUTE FUNCTION trigger_set_updated_at();

-- ── package_suggestions (anónimo) ────────────────────────────────────────────
-- workflow:
--   pending     →  promoted   (admin promovió a bank_packages, set promoted_to_id)
--   pending     →  rejected   (admin descartó la propuesta)
--   pending     →  duplicate  (ya existe en bank_packages — no fue necesario promover)
-- El estado terminal es informativo; no hay GC automático todavía. Las filas
-- son cortas (3 columnas TEXT cortas) y útiles longitudinalmente para evaluar
-- coverage del catálogo global.
CREATE TABLE package_suggestions (
    id                  uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    package_name        TEXT         NOT NULL,
    proposed_bank_id    TEXT,
    proposed_label      TEXT         NOT NULL,

    status              TEXT         NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','promoted','rejected','duplicate')),
    promoted_to_id      uuid REFERENCES bank_packages (id),
    reviewed_at         timestamptz,

    created_at          timestamptz  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_package_suggestions_status
    ON package_suggestions (status, created_at DESC);

CREATE INDEX idx_package_suggestions_pending_package
    ON package_suggestions (package_name)
    WHERE status = 'pending';
