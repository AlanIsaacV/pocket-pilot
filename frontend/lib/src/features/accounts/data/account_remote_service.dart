// ============================================================
// AccountRemoteService — wrapper delgado de gRPC para cuentas
// ============================================================
//
// Responsabilidades:
//   1. Construir el request proto correcto.
//   2. Llamar al servidor.
//   3. Retornar la respuesta proto (sin convertir — eso lo hace el handler).
//   4. Re-lanzar GrpcError como excepción estándar.
//
// Los métodos soportan el nuevo contrato de sync:
//   listAccounts  → acepta updated_since para delta pull
//   upsertAccount → create + update unificados, retorna conflict_resolved (LWW)
//   deleteAccount → soft delete con timestamp LWW

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountRemoteService {
  late final AccountServiceClient _client;

  AccountRemoteService() {
    _client = AccountServiceClient(GrpcClient.channel);
  }

  // ----------------------------------------------------------
  // PULL
  // ----------------------------------------------------------

  /// Lista cuentas del usuario.
  ///
  /// Si [updatedSince] es null → primer sync (trae todas las cuentas activas).
  /// Si [updatedSince] está definido → delta sync (solo cuentas modificadas
  /// después de ese timestamp).
  ///
  /// Retorna la respuesta completa (incluye synced_at para actualizar el cursor).
  Future<ListAccountsResponse> listAccounts(
    String userId, {
    DateTime? updatedSince,
  }) async {
    try {
      final request = ListAccountsRequest(userId: userId);
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listAccounts(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listAccounts error: ${e.message}');
    }
  }

  // ----------------------------------------------------------
  // PUSH
  // ----------------------------------------------------------

  /// Crea o actualiza una cuenta en el servidor (upsert).
  ///
  /// [map] es el payload del outbox (incluye user_id y todos los campos).
  /// Retorna UpsertAccountResponse con:
  ///   - account: versión aceptada (cliente o servidor según LWW).
  ///   - conflict_resolved: true si el servidor tenía versión más reciente.
  Future<UpsertAccountResponse> upsertAccount(Map<String, dynamic> map) async {
    try {
      final account = _buildProto(map);
      return await _client.upsertAccount(UpsertAccountRequest(account: account));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertAccount error: ${e.message}');
    }
  }

  /// Elimina lógicamente una cuenta. Aplica LWW: solo hace el delete
  /// si el servidor no tiene una versión más reciente.
  Future<void> deleteAccount({
    required String id,
    required String userId,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteAccount(
        DeleteAccountRequest(
          id: id,
          userId: userId,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteAccount error: ${e.message}');
    }
  }

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  /// Construye un proto Account desde el payload Map del outbox.
  Account _buildProto(Map<String, dynamic> map) {
    final creditLimitCents = map['credit_limit_cents'] as int?;
    final statementDay = map['statement_day'] as int?;
    final paymentDueDay = map['payment_due_day'] as int?;
    final interestRateApr = map['interest_rate_apr'] as int?;
    final termMonths = map['term_months'] as int?;

    return Account(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      name: map['name'] as String,
      type: AccountModel.stringToAccountType(map['type'] as String),
      creditLimitCents:
          creditLimitCents != null ? Int64(creditLimitCents) : null,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: Timestamp.fromDateTime(
          DateTime.parse(map['created_at'] as String).toUtc()),
      updatedAt: Timestamp.fromDateTime(
          DateTime.parse(map['updated_at'] as String).toUtc()),
    );
  }
}
