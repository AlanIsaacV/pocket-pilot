import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/db/database_helper.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final TokenStore _tokenStore;
  final DatabaseHelper _dbHelper;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  AuthProvider({
    required AuthService authService,
    required TokenStore tokenStore,
    required DatabaseHelper dbHelper,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _dbHelper = dbHelper;

  Future<void> init() async {
    _isAuthenticated = await _tokenStore.hasTokens();
    notifyListeners();
  }

  Future<void> loginWithGoogle() async {
    final idToken = await _authService.loginWithGoogle();
    await _authService.authenticate(provider: 'google', idToken: idToken);
    await _clearDbIfUserChanged();
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> loginWithApple() async {
    final idToken = await _authService.loginWithApple();
    await _authService.authenticate(provider: 'apple', idToken: idToken);
    await _clearDbIfUserChanged();
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.logout();
    _isAuthenticated = false;
    notifyListeners();
  }

  Future<void> revokeAllSessions() async {
    await _authService.revokeAllSessions();
    _isAuthenticated = false;
    notifyListeners();
  }

  void forceLogout() {
    _tokenStore.clear();
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Compares the newly authenticated userId with the last one stored in
  /// app_metadata. If they differ, wipes the local DB so sync can repopulate
  /// it with the correct user's data.
  Future<void> _clearDbIfUserChanged() async {
    final newUserId = await _tokenStore.getUserId();
    if (newUserId == null) return;

    final db = await _dbHelper.database;
    final rows = await db.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: ['last_user_id'],
    );

    final lastUserId = rows.isNotEmpty ? rows.first['value'] as String? : null;

    if (lastUserId != null && lastUserId != newUserId) {
      // Different user — wipe and recreate.
      await DatabaseHelper.deleteAndReset();
      final freshDb = await _dbHelper.database;
      await freshDb.insert(
        'app_metadata',
        {'key': 'last_user_id', 'value': newUserId},
      );
    } else if (lastUserId == null) {
      // First login ever — just store the userId.
      await db.insert(
        'app_metadata',
        {'key': 'last_user_id', 'value': newUserId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
