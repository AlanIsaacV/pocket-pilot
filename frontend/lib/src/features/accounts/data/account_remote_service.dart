// ============================================================
// AccountRemoteService — wrapper delgado de gRPC para cuentas
// ============================================================
//
// Esta clase es un wrapper delgado sobre el cliente gRPC generado.
// Su única responsabilidad es:
//   1. Construir el request proto correcto.
//   2. Llamar al servidor.
//   3. Retornar el proto de respuesta (sin convertir — eso lo hace el repo).
//   4. Re-lanzar GrpcError como excepción manejable.

// Int64 es el tipo Dart para campos int64 en protobuf.
// El paquete fixnum es una dependencia TRANSITIVA de protobuf:
// no necesitas agregarlo en pubspec.yaml.
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
// account_service.pbgrpc.dart ya re-exporta account_service.pb.dart y pbenum.dart,
// por lo que un solo import es suficiente para AccountServiceClient, Account,
// AccountType, CreateAccountRequest, etc.
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbgrpc.dart';
// common.pb.dart NO es re-exportado por pbgrpc, necesitamos importarlo para Money.
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class AccountRemoteService {
  // Creamos el cliente gRPC usando el canal compartido.
  // AccountServiceClient es generado automáticamente desde el .proto.
  late final AccountServiceClient _client;

  AccountRemoteService() {
    _client = AccountServiceClient(GrpcClient.channel);
  }

  /// Lista todas las cuentas del usuario.
  /// Retorna la lista de objetos [Account] (proto).
  Future<List<Account>> listAccounts(String userId) async {
    try {
      final response = await _client.listAccounts(
        ListAccountsRequest(userId: userId),
      );
      return response.accounts;
    } on GrpcError catch (e) {
      // GrpcError tiene un código de estado (e.code) y mensaje (e.message).
      // Lo re-lanzamos como Exception estándar para que el repositorio
      // pueda capturarlo sin depender de la librería grpc.
      throw Exception('gRPC listAccounts error: ${e.message}');
    }
  }

  /// Crea una nueva cuenta en el servidor.
  Future<Account> createAccount({
    required String userId,
    required String name,
    required AccountType type,
    required int initialBalanceMinor,
    required String currencyCode,
  }) async {
    try {
      final response = await _client.createAccount(
        CreateAccountRequest(
          userId: userId,
          name: name,
          type: type,
          initialBalance: Money(
            // Int64(valor) crea un entero de 64 bits desde un int nativo de Dart.
            amountMinor: Int64(initialBalanceMinor),
            currencyCode: currencyCode,
          ),
        ),
      );
      return response.account;
    } on GrpcError catch (e) {
      throw Exception('gRPC createAccount error: ${e.message}');
    }
  }

  /// Elimina una cuenta por su ID.
  Future<void> deleteAccount({
    required String userId,
    required String accountId,
  }) async {
    try {
      await _client.deleteAccount(
        DeleteAccountRequest(userId: userId, accountId: accountId),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteAccount error: ${e.message}');
    }
  }
}
