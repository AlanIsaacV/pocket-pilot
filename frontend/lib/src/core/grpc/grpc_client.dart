// ============================================================
// Cliente gRPC — canal compartido (singleton)
// ============================================================
//
// gRPC usa HTTP/2 como transporte. Crear un ClientChannel es
// costoso (negociación TLS, handshake HTTP/2), por lo que usamos
// el patrón singleton para reutilizar la misma conexión en toda
// la app. Es seguro usar un canal desde múltiples isolates/threads.

import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';

class GrpcClient {
  // Constructor privado: nadie puede instanciar esta clase.
  GrpcClient._();

  // Canal singleton. El signo ? indica que puede ser null (no inicializado aún).
  static ClientChannel? _channel;

  /// Retorna el canal singleton, inicializándolo la primera vez.
  /// El operador ??= significa "asigna sólo si es null".
  static ClientChannel get channel {
    _channel ??= ClientChannel(
      kGrpcHost,
      port: kGrpcPort,
      options: const ChannelOptions(
        // ChannelCredentials.insecure() → sin TLS.
        // SÓLO para desarrollo local. En producción usar:
        //   credentials: ChannelCredentials.secure()
        // y configurar un certificado válido en el servidor.
        credentials: ChannelCredentials.insecure(),
      ),
    );
    return _channel!;
  }

  /// Cierra el canal y libera recursos.
  /// Llamar en el dispose() del widget raíz o cuando la app se cierra.
  static Future<void> dispose() async {
    await _channel?.shutdown();
    _channel = null;
  }
}
