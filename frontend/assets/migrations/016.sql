-- Fase 8: package selection dinámica + loop comunitario.
--
-- Cuatro tablas nuevas que reemplazan la allowlist hardcoded del NLS Kotlin:
--
--   package_observations    Local-only, sin PII. Cada noti que llega al NLS
--                           hace UPSERT aquí (package_name + count + last_seen).
--                           Pobla el picker "Mis bancos". Misma retención
--                           de 90d que captured_notifications.
--
--   watched_packages        Local-only. Per-device toggle de qué packages
--                           procesa el NLS aquí. Sin outbox: la decisión
--                           "capturar BBVA en este device" es per-device.
--                           El NLS Kotlin lee enabled=1 antes de guardar
--                           a captured_notifications.
--
--   bank_aliases            Sincronizable (push+pull, LWW), mismo patrón
--                           que account_card_mappings. Per-user: el alias
--                           "Mi BBVA" se sincroniza entre devices del mismo
--                           usuario para aparecer como hint sugerido.
--
--   bank_packages           Cache local del catálogo global pull-only.
--                           Mismo patrón que notification_parsers. El admin
--                           promueve entradas server-side y el cliente las
--                           recoge en el siguiente sync.
--
-- Migración seed: BBVA México. Antes de Fase 8 el NLS tenía hardcoded
-- com.bbva.bancomermovil y com.bancomer.mbanking; los seedeamos en
-- watched_packages para que existing users no pierdan la captura tras update.
-- bank_aliases NO se seed: que el usuario lo cree organicamente al pasar
-- por el picker (bank_packages global ya tiene la entrada, así que la
-- resolución de bank_id sigue funcionando).

-- ── package_observations ─────────────────────────────────────────────────────
CREATE TABLE package_observations (
    package_name   TEXT     PRIMARY KEY,
    first_seen_at  DATETIME NOT NULL,
    last_seen_at   DATETIME NOT NULL,
    noti_count     INTEGER  NOT NULL DEFAULT 1,
    purged_at      DATETIME
);
CREATE INDEX idx_package_observations_last_seen_active
    ON package_observations (last_seen_at)
    WHERE purged_at IS NULL;

-- Backfill: si el dispositivo ya tiene captured_notifications de versiones
-- anteriores, hidratamos el log con esos datos para que el picker tenga
-- contenido al primer abrir post-update.
INSERT INTO package_observations (package_name, first_seen_at, last_seen_at, noti_count)
SELECT
    package_name,
    MIN(posted_at) AS first_seen_at,
    MAX(posted_at) AS last_seen_at,
    COUNT(*)       AS noti_count
FROM captured_notifications
WHERE package_name IS NOT NULL
GROUP BY package_name;

-- ── watched_packages ─────────────────────────────────────────────────────────
CREATE TABLE watched_packages (
    id              TEXT     PRIMARY KEY,
    package_name    TEXT     NOT NULL UNIQUE,
    enabled         INTEGER  NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TRIGGER set_updated_at_watched_packages
    AFTER UPDATE
    ON watched_packages
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE watched_packages
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

-- Seed: BBVA (allowlist hardcoded pre-Fase-8). UUIDs determinísticos para
-- que dos devices del mismo usuario que migran a la vez no tengan colisión
-- de natural key.
INSERT INTO watched_packages (id, package_name, enabled) VALUES
    ('00000000-0000-4000-8000-bbva0000bbva', 'com.bbva.bancomermovil', 1),
    ('00000000-0000-4000-8000-bbva0000mbnk', 'com.bancomer.mbanking',  1);

-- ── bank_aliases ─────────────────────────────────────────────────────────────
CREATE TABLE bank_aliases (
    id              TEXT     PRIMARY KEY,
    package_name    TEXT     NOT NULL UNIQUE,
    bank_id         TEXT,
    display_label   TEXT     NOT NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at      DATETIME
);
CREATE INDEX idx_bank_aliases_lookup
    ON bank_aliases (package_name)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_bank_aliases_updated_at
    ON bank_aliases (updated_at);
CREATE TRIGGER set_updated_at_bank_aliases
    AFTER UPDATE
    ON bank_aliases
    FOR EACH ROW
    WHEN new.updated_at = old.updated_at
BEGIN
    UPDATE bank_aliases
    SET updated_at = CURRENT_TIMESTAMP
    WHERE id = new.id;
END;

-- ── bank_packages (cache local del catálogo global) ──────────────────────────
CREATE TABLE bank_packages (
    package_name    TEXT     PRIMARY KEY,
    bank_id         TEXT     NOT NULL,
    default_label   TEXT     NOT NULL,
    is_active       INTEGER  NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at      DATETIME
);
CREATE INDEX idx_bank_packages_active
    ON bank_packages (bank_id)
    WHERE deleted_at IS NULL AND is_active = 1;
CREATE INDEX idx_bank_packages_updated_at
    ON bank_packages (updated_at);

-- Seed inicial: BBVA. La fila se reemplaza cuando el primer sync de
-- bank_package llegue desde backend con su versión canónica.
INSERT INTO bank_packages (package_name, bank_id, default_label) VALUES
    ('com.bbva.bancomermovil', 'bbva_mx', 'BBVA'),
    ('com.bancomer.mbanking',  'bbva_mx', 'BBVA');
