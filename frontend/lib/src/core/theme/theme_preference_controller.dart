import 'package:flutter/material.dart';

import 'package:pocket_pilot/src/features/user_preferences/data/theme_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/theme_preferences.dart';

class ThemePreferenceController extends ChangeNotifier {
  final ThemePreferencesLocalStore _localStore;
  final UserPreferenceRepository _repository;

  AppThemePreference _preference = kInitialThemePreference;
  bool _isLoaded = false;

  ThemePreferenceController({
    required ThemePreferencesLocalStore localStore,
    required UserPreferenceRepository repository,
  }) : _localStore = localStore,
       _repository = repository;

  AppThemePreference get preference => _preference;

  bool get isLoaded => _isLoaded;

  ThemeMode get themeMode => appThemePreferenceToThemeMode(_preference);

  String get label => appThemePreferenceLabel(_preference);

  Future<void> loadFromLocal() async {
    final localPreference = await _localStore.getThemePreference();
    _setPreference(localPreference, markLoaded: true);
  }

  Future<void> savePreference(AppThemePreference value) async {
    await _repository.upsertPreference(
      prefKey: kThemeModePrefKey,
      prefValue: appThemePreferenceToStorage(value),
    );
    _setPreference(value, markLoaded: true);
  }

  void _setPreference(AppThemePreference value, {required bool markLoaded}) {
    final shouldNotify = value != _preference || (_isLoaded != markLoaded);
    _preference = value;
    _isLoaded = markLoaded;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}
