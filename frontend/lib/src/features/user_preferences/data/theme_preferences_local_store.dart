import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/theme_preferences.dart';

class ThemePreferencesLocalStore {
  final UserPreferenceLocalStore _preferences;

  ThemePreferencesLocalStore({required UserPreferenceLocalStore preferences})
    : _preferences = preferences;

  Future<AppThemePreference> getThemePreference() async {
    final pref = await _preferences.getByKey(kThemeModePrefKey);
    return parseAppThemePreference(pref?.prefValue);
  }
}
