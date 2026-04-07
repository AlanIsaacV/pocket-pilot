import 'dart:async';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/token_store.dart';

class AuthInterceptor implements ClientInterceptor {
  final TokenStore _tokenStore;

  AuthInterceptor({required TokenStore tokenStore}) : _tokenStore = tokenStore;

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
      options.mergedWith(CallOptions(providers: [_addAuthMetadata])),
    );
  }

  Future<void> _addAuthMetadata(
    Map<String, String> metadata,
    String uri,
  ) async {
    final token = await _tokenStore.getAccessToken();
    if (token != null) {
      metadata['authorization'] = 'Bearer $token';
    }
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
      options.mergedWith(CallOptions(providers: [_addAuthMetadata])),
    );
  }
}
