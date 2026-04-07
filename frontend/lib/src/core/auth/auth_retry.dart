import 'dart:async';

import 'package:grpc/grpc.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';

class AuthRetry {
  final AuthService _authService;
  final AuthProvider _authProvider;

  Completer<bool>? _refreshCompleter;

  AuthRetry({
    required AuthService authService,
    required AuthProvider authProvider,
  })  : _authService = authService,
        _authProvider = authProvider;

  Future<T> call<T>(Future<T> Function() grpcCall) async {
    try {
      return await grpcCall();
    } on GrpcError catch (e) {
      if (e.code != StatusCode.unauthenticated) rethrow;
    }

    final refreshed = await _serializedRefresh();
    if (!refreshed) {
      _authProvider.forceLogout();
      throw GrpcError.unauthenticated('Session expired. Please log in again.');
    }

    return await grpcCall();
  }

  Future<bool> _serializedRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final result = await _authService.refresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}
