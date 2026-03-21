// ============================================================
// AccountRepository — orquestación offline-first para cuentas
// ============================================================
//
// Patrón "offline-first":
//   getAccounts()        → lee local (instantáneo)
//   syncAndGetAccounts() → sincroniza con el servidor, persiste local, devuelve resultado
//
// Este repositorio no contiene SQL: delega toda persistencia en
// AccountLocalStore y toda comunicación remota en AccountRemoteService.

import 'dart:async';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbenum.dart';

class AccountRepository {
  final AccountLocalStore _local;
  final AccountRemoteService _remote;

  AccountRepository({
    required AccountLocalStore local,
    required AccountRemoteService remote,
  })  : _local = local,
        _remote = remote;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Lee las cuentas almacenadas localmente (sin contactar al servidor).
  Future<List<AccountModel>> getAccounts(String userId) =>
      _local.getAccounts(userId);

  /// Descarga cuentas del servidor y las persiste en SQLite.
  ///
  /// A diferencia de [syncAndGetAccounts], este método propaga los errores
  /// para que el ViewModel pueda mostrarlos al usuario.
  Future<void> syncRemote(String userId) async {
    final remoteAccounts = await _remote.listAccounts(userId);
    await _local.upsertAll(
      remoteAccounts.map(AccountModel.fromProto).toList(),
    );
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Crea una cuenta local primero (respuesta inmediata en UI),
  /// luego intenta sincronizar con el servidor en background.
  Future<void> createAccount({
    required String id, // UUID generado en el cliente
    required String userId,
    required String name,
    required String type,
    required int initialBalanceMinor,
    required String currencyCode,
  }) async {
    final now = DateTime.now().toUtc();

    // Construimos el modelo y lo persistimos localmente de inmediato.
    await _local.upsert(AccountModel(
      id: id,
      userId: userId,
      name: name,
      type: type,
      initialBalance: initialBalanceMinor,
      currencyCode: currencyCode,
      createdAt: now,
      updatedAt: now,
    ));

    // Sincroniza con el servidor en background.
    unawaited(() async {
      try {
        await _remote.createAccount(
          userId: userId,
          name: name,
          type: _stringToAccountType(type),
          initialBalanceMinor: initialBalanceMinor,
          currencyCode: currencyCode,
        );
      } catch (_) {
        // TODO: en producción marcar como "pendiente de sync" y reintentar.
      }
    }());
  }

  /// Convierte nuestro string de tipo al enum proto para enviarlo al servidor.
  static AccountType _stringToAccountType(String type) {
    switch (type) {
      case 'savings':
        return AccountType.ACCOUNT_TYPE_SAVINGS;
      case 'credit_card':
        return AccountType.ACCOUNT_TYPE_CREDIT_CARD;
      case 'cash':
        return AccountType.ACCOUNT_TYPE_CASH;
      case 'investment':
        return AccountType.ACCOUNT_TYPE_INVESTMENT;
      default:
        return AccountType.ACCOUNT_TYPE_CHECKING;
    }
  }
}
