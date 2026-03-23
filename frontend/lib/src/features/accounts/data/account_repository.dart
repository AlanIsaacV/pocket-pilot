// ============================================================
// AccountRepository — capa de orquestación de la feature Accounts
// ============================================================
//
// Patrón offline-first con Outbox:
//   getAccounts()    → lee SQLite local (instantáneo, siempre funciona)
//   createAccount()  → escribe en SQLite + encola en sync_outbox
//   deleteAccount()  → soft-delete en SQLite + encola en sync_outbox
//
// El repositorio NO llama directamente al servidor.
// SyncService es el responsable de flushear el outbox cuando hay conexión.

import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountRepository {
  final AccountLocalStore _local;
  final SyncOutbox _outbox;

  AccountRepository({
    required AccountLocalStore local,
    required SyncOutbox outbox,
  })  : _local = local,
        _outbox = outbox;

  // ----------------------------------------------------------
  // READ — siempre desde SQLite local
  // ----------------------------------------------------------

  /// Lee las cuentas almacenadas localmente.
  /// Nunca contacta al servidor; la sync es responsabilidad de SyncService.
  Future<List<AccountModel>> getAccounts() => _local.getAccounts();

  // ----------------------------------------------------------
  // WRITE — local primero, luego outbox para sync posterior
  // ----------------------------------------------------------

  /// Crea una cuenta localmente y la encola para sync remoto.
  ///
  /// La UI responde inmediatamente (escribe en SQLite).
  /// SyncService enviará la cuenta al servidor cuando haya conexión.
  Future<void> createAccount({
    required String id, // UUID generado en el cliente
    required String userId,
    required String name,
    required String type,
    int? creditLimitCents,
    int? statementDay,
    int? paymentDueDay,
    int? interestRateApr,
    int? termMonths,
  }) async {
    final now = DateTime.now().toUtc();
    final model = AccountModel(
      id: id,
      userId: userId,
      name: name,
      type: type,
      creditLimitCents: creditLimitCents,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: now,
      updatedAt: now,
    );

    // 1. Persistir localmente: UI actualizada inmediatamente.
    await _local.upsert(model);

    // 2. Encolar para sync: SyncService flushea cuando haya conexión.
    // toServerMap() incluye user_id para el servidor.
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  /// Elimina lógicamente una cuenta y encola el delete para sync remoto.
  Future<void> deleteAccount(String id, String userId) async {
    final now = DateTime.now().toUtc();

    // 1. Soft delete local.
    await _local.softDelete(id, now);

    // 2. Encolar delete para el servidor.
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({
        'user_id': userId,
        'deleted_at': now.toIso8601String(),
      }),
    );
  }
}
