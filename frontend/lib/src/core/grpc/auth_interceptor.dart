import 'package:grpc/grpc.dart';

/// Interceptor gRPC que agrega el header de autorización MVP a todas las requests.
///
/// En producción, el token vendría de secure_storage o un sistema de auth real.
/// Para el MVP, usamos un token hardcodeado que el servidor valida.
const _kMvpToken = 'Bearer MVP-TOKEN-123';

/// MVP user ID that the backend maps to 'Bearer MVP-TOKEN-123'.
/// Replace with the real authenticated user ID when auth is implemented.
const kMvpUserId = '00000000-0000-0000-0000-000000000001';

class AuthInterceptor implements ClientInterceptor {
  const AuthInterceptor();

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    return invoker(
      method,
      request,
      options.mergedWith(CallOptions(metadata: {'authorization': _kMvpToken})),
    );
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    return invoker(
      method,
      requests,
      options.mergedWith(CallOptions(metadata: {'authorization': _kMvpToken})),
    );
  }
}
