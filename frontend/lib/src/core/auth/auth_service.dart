import 'package:google_sign_in/google_sign_in.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/auth_service.pbgrpc.dart';

class AuthService {
  final TokenStore _tokenStore;
  final String? _googleServerClientId;
  late final AuthServiceClient _client;
  bool _googleSignInInitialized = false;

  AuthService({
    TokenStore? tokenStore,
    AuthServiceClient? client,
    String? googleServerClientId,
  })  : _tokenStore = tokenStore ?? TokenStore(),
        _googleServerClientId = googleServerClientId {
    _client = client ?? AuthServiceClient(GrpcClient.channel);
  }

  /// Signs in with Google and returns the OIDC id_token.
  Future<String> loginWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    if (!_googleSignInInitialized) {
      await googleSignIn.initialize(
        serverClientId: _googleServerClientId,
      );
      _googleSignInInitialized = true;
    }
    final account = await googleSignIn.authenticate(
      scopeHint: ['email'],
    );
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in did not return an id_token.');
    }
    return idToken;
  }

  /// Signs in with Apple and returns the identity token.
  Future<String> loginWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
    );
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw Exception('Apple sign-in did not return an identity token.');
    }
    return identityToken;
  }

  /// Calls OAuthLogin on the gRPC server and persists the returned tokens.
  Future<void> authenticate({
    required String provider,
    required String idToken,
  }) async {
    final response = await _client.oAuthLogin(
      OAuthLoginRequest(provider: provider, idToken: idToken),
    );
    await _tokenStore.save(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      userId: response.userId,
    );
  }

  /// Attempts to refresh the access token. Returns true on success.
  Future<bool> refresh() async {
    try {
      final storedRefreshToken = await _tokenStore.getRefreshToken();
      if (storedRefreshToken == null) return false;

      final response = await _client.refreshToken(
        RefreshRequest(refreshToken: storedRefreshToken),
      );
      await _tokenStore.save(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        userId: response.userId,
      );
      return true;
    } on GrpcError {
      return false;
    }
  }

  /// Logs out by invalidating the refresh token on the server, then clears
  /// locally stored tokens. Best-effort: local tokens are always cleared even
  /// if the server call fails.
  Future<void> logout() async {
    try {
      final storedRefreshToken = await _tokenStore.getRefreshToken();
      if (storedRefreshToken != null) {
        await _client.logout(
          LogoutRequest(refreshToken: storedRefreshToken),
        );
      }
    } on GrpcError catch (_) {
      // Best-effort: proceed to clear local tokens regardless.
    } finally {
      await _tokenStore.clear();
    }
  }

  /// Revokes all active sessions for the user on the server, then clears
  /// locally stored tokens. Best-effort: local tokens are always cleared.
  Future<void> revokeAllSessions() async {
    try {
      await _client.revokeAllSessions(Empty());
    } on GrpcError catch (_) {
      // Best-effort: proceed to clear local tokens regardless.
    } finally {
      await _tokenStore.clear();
    }
  }
}
