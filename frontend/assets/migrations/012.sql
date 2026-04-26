-- Reparación: en versiones tempranas del feature notification_capture la
-- migración 008 se actualizó in-place agregando la columna
-- `suggested_category_id` después de que algunos devices ya la habían
-- corrido. Esos devices quedaron con el schema viejo y ahora el INSERT
-- de PendingTransactionLocalStore.insert falla con
-- "table pending_transactions has no column named suggested_category_id".
--
-- Esta migración añade la columna idempotentemente. SQLite no soporta
-- "ADD COLUMN IF NOT EXISTS"; por eso intentamos el ALTER y dejamos que
-- migrations_runner ignore el error de columna duplicada en devices que
-- ya la tienen (el runner no maneja excepciones por fila, así que en
-- devices nuevos esto solo corre una vez tras 008 idempotente).
--
-- Nota: SQLite no permite agregar columnas con REFERENCES; la integridad
-- referencial a categories se valida a nivel aplicación.

ALTER TABLE pending_transactions ADD COLUMN suggested_category_id TEXT;
