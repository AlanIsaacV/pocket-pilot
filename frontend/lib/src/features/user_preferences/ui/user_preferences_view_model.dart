import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/theme_preferences.dart';

class UserPreferencesViewModel extends ChangeNotifier {
  final UserPreferenceRepository _repository;
  final SyncService _syncService;

  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;

  List<String> allowedCurrencies = [];
  String defaultCurrency = kInitialDefaultCurrency;
  AppThemePreference themePreference = kInitialThemePreference;

  UserPreferencesViewModel({
    required UserPreferenceRepository repository,
    required SyncService syncService,
  }) : _repository = repository,
       _syncService = syncService;

  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  Future<void> refresh() => _runSync();

  Future<void> saveCurrencies({
    required List<String> allowed,
    required String defaultCode,
  }) async {
    final normalizedAllowed = _normalizeCodes(allowed);
    final normalizedDefault = normalizeCurrencyCode(defaultCode);

    if (normalizedAllowed.isEmpty) {
      throw Exception('Debes mantener al menos una moneda permitida.');
    }
    if (!isValidCurrencyCode(normalizedDefault)) {
      throw Exception('La moneda por defecto no es valida.');
    }
    if (!normalizedAllowed.contains(normalizedDefault)) {
      throw Exception('La moneda por defecto debe estar en las permitidas.');
    }

    final now = DateTime.now().toUtc();
    await _repository.upsertPreference(
      prefKey: kAllowedCurrenciesPrefKey,
      prefValue: jsonEncode(normalizedAllowed),
      forcedUpdatedAt: now,
    );
    await _repository.upsertPreference(
      prefKey: kDefaultCurrencyPrefKey,
      prefValue: normalizedDefault,
      forcedUpdatedAt: now,
    );

    await _reloadLocal();
    await _runSync();
  }

  Future<void> saveThemePreference(AppThemePreference preference) async {
    await _repository.upsertPreference(
      prefKey: kThemeModePrefKey,
      prefValue: appThemePreferenceToStorage(preference),
    );
    themePreference = preference;
    notifyListeners();
    await _runSync();
  }

  Future<void> _loadLocalThenMaybeSync() async {
    await _ensureSeededLocally();
    await _reloadLocal();
    await _runSync();
  }

  Future<void> _runSync() async {
    isLoading = allowedCurrencies.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _syncService.sync();
      await _ensureSeededLocally();
      await _reloadLocal();
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _reloadLocal() async {
    final allowedPref = await _repository.getByKey(kAllowedCurrenciesPrefKey);
    final defaultPref = await _repository.getByKey(kDefaultCurrencyPrefKey);
    final themePref = await _repository.getByKey(kThemeModePrefKey);

    final snapshot = buildCurrencyPreferencesSnapshot(
      allowedRaw: allowedPref?.prefValue,
      defaultRaw: defaultPref?.prefValue,
    );

    allowedCurrencies = snapshot.allowedCodes;
    defaultCurrency = snapshot.defaultCode;
    themePreference = parseAppThemePreference(themePref?.prefValue);
    notifyListeners();
  }

  Future<void> _ensureSeededLocally() async {
    final allowedPref = await _repository.getByKey(kAllowedCurrenciesPrefKey);
    final defaultPref = await _repository.getByKey(kDefaultCurrencyPrefKey);
    final themePref = await _repository.getByKey(kThemeModePrefKey);
    if (allowedPref != null && defaultPref != null && themePref != null) {
      return;
    }

    final bootstrapTs = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (allowedPref == null) {
      await _repository.upsertPreference(
        prefKey: kAllowedCurrenciesPrefKey,
        prefValue: jsonEncode(kInitialAllowedCurrencies),
        forcedUpdatedAt: bootstrapTs,
      );
    }
    if (defaultPref == null) {
      await _repository.upsertPreference(
        prefKey: kDefaultCurrencyPrefKey,
        prefValue: kInitialDefaultCurrency,
        forcedUpdatedAt: bootstrapTs,
      );
    }
    if (themePref == null) {
      await _repository.upsertPreference(
        prefKey: kThemeModePrefKey,
        prefValue: appThemePreferenceToStorage(kInitialThemePreference),
        forcedUpdatedAt: bootstrapTs,
      );
    }
  }

  static List<String> _normalizeCodes(List<String> codes) {
    return normalizeCurrencyCodes(codes);
  }
}
