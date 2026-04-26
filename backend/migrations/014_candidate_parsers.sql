-- candidate_parsers: samples y propuestas de regex generados por el LLM
-- cuando un parser local no reconoce una notificación. La mejora de
-- `notification_parsers` es humano-in-the-loop: un admin revisa las filas en
-- estado 'pending', valida (o reescribe) el regex propuesto y lo promueve
-- vía UPDATE SQL sobre notification_parsers.
--
-- Privacidad: la tabla NO referencia user_id. Los samples se almacenan
-- anónimamente. El control de persistencia vive en el cliente (toggle
-- `help_improve_app`); si está OFF, el handler de ParseNotification responde
-- al usuario pero no inserta aquí.
--
-- workflow:
--   pending → promoted   (admin la promovió a un parser global)
--   pending → rejected   (admin descartó la propuesta)
-- El estado terminal es informativo; no hay GC automático todavía.

CREATE TABLE candidate_parsers (
    id                   uuid PRIMARY KEY      DEFAULT gen_random_uuid(),
    bank_id              TEXT         NOT NULL,
    package_name         TEXT         NOT NULL,

    -- sample original (anonimizado: solo title/text/big_text)
    sample_title         TEXT,
    sample_text          TEXT,
    sample_big_text      TEXT,

    -- propuesta del LLM
    proposed_pattern_id  TEXT,
    proposed_regex       TEXT,
    proposed_tx_type     TEXT,
    proposed_currency    TEXT,
    extracted_fields     JSONB        NOT NULL,

    -- metadatos del LLM
    llm_provider         TEXT         NOT NULL,
    llm_model_version    TEXT         NOT NULL,
    llm_confidence       NUMERIC,

    -- workflow admin
    status               TEXT         NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','promoted','rejected')),
    promoted_to_bank_id  TEXT,
    promoted_version     INT,
    reviewed_at          timestamptz,

    created_at           timestamptz  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_candidate_parsers_status_bank
    ON candidate_parsers (status, bank_id, created_at DESC);
