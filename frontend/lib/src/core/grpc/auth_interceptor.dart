import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';

/// gRPC [ClientInterceptor] that attaches the current access token to every
/// outgoing request and proactively refreshes it when it is expired or about
/// to expire.
///
/// Refresh is performed inside the [CallOptions.providers] callback so it
/// happens *before* the request is sent — this avoids relying on response-side
/// retry, which is awkward in gRPC-Dart because [ResponseFuture] can only be
/// constructed from an internal [ClientCall].
///
/// Concurrent calls that trigger a refresh simultaneously are serialized via a
/// single [Completer], so only one [AuthService.refresh] RPC is issued even
/// under heavy concurrency (e.g. parallel sync).
class AuthInterceptor implements ClientInterceptor {
  /// Refresh when the access token is within this window of its exp claim.
  /// Covers small client/server clock skew and network latency.
  static const _expiryGrace = Duration(seconds: 30);

  final TokenStore _tokenStore;
  final AuthService _authService;
  final AuthProvider _authProvider;

  Completer<bool>? _refreshCompleter;

  AuthInterceptor({
    required TokenStore tokenStore,
    required AuthService authService,
    required AuthProvider authProvider,
  })  : _tokenStore = tokenStore,
        _authService = authService,
        _authProvider = authProvider;

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

  Future<void> _addAuthMetadata(
    Map<String, String> metadata,
    String uri,
  ) async {
    var token = await _tokenStore.getAccessToken();
    if (token == null) return;

    if (_isExpiredOrExpiringSoon(token)) {
      final refreshed = await _serializedRefresh();
      if (!refreshed) {
        _authProvider.forceLogout();
        throw GrpcError.unauthenticated(
          'Session expired. Please log in again.',
        );
      }
      token = await _tokenStore.getAccessToken();
      if (token == null) return;
    }

    metadata['authorization'] = 'Bearer $token';
  }

  /// Returns true if the JWT is already expired or will expire within
  /// [_expiryGrace]. Returns false when the exp claim cannot be decoded
  /// (malformed token) so the request is attempted and the server decides.
  bool _isExpiredOrExpiringSoon(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is! int) return false;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return DateTime.now().toUtc().isAfter(expiresAt.subtract(_expiryGrace));
    } catch (_) {
      return false;
    }
  }

  /// Ensures at most one concurrent [AuthService.refresh] call. Follow-up
  /// callers await the in-flight completer instead of issuing a new RPC.
  Future<bool> _serializedRefresh() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    try {
      final result = await _authService.refresh();
      completer.complete(result);
      return result;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}
