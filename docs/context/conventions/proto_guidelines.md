# Protobuf Guidelines

This document outlines the conventions for defining gRPC services and messages in the Pocket Pilot project.

## General Principles
- **Backwards Compatibility:** Never remove or rename fields. Use `reserved` if a field is deprecated.
- **CamelCase:** Use `PascalCase` for message names and `snake_case` for field names.
- **Package Naming:** Follow the structure `pocket_pilot.v1`.

## Service Definitions
Every entity should have its own `.proto` file (e.g., `account_service.proto`).

### Service Structure
Standard sync-oriented services **MUST** implement:
- `List<Entity>Request`: Should include `updated_since` (optional Timestamp) and `page` (optional PageRequest). `user_id` is inferred from authenticated context in handlers.
- `List<Entity>Response`: Should include the list of entities, `page` (PageResponse), and `synced_at` (Timestamp).
- `Upsert<Entity>Request`: Should wrap the full entity message.
- `Upsert<Entity>Response`: Should include the updated entity and a `conflict_resolved` boolean.
- `Delete<Entity>Request`: Should include entity identity fields (e.g., `id` or `pref_key`) and `deleted_at` (Timestamp) for LWW soft deletes.

## Message Conventions
- **IDs:** Use `string` for UUIDs.
- **Timestamps:** Use `google.protobuf.Timestamp` for all dates/times.
- **Money:** Use the common `Money` message defined in `common.proto` for all monetary values.
- **Enums:** Start enum value names with the enum name (e.g., `ACCOUNT_TYPE_BANK`).
- **Required domain fields:** For MVP entity contracts, include required persistence attributes explicitly in the entity message (for example, `Account.currency_code`) so frontend/backed mappings remain symmetric.

## Code Generation
Always run `make proto` from the root directory after any change to a `.proto` file.
