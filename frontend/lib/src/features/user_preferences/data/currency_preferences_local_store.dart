import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';

class CurrencyPreferencesLocalStore {
  final UserPreferenceLocalStore _preferences;

  CurrencyPreferencesLocalStore({required UserPreferenceLocalStore preferences})
    : _preferences = preferences;

  Future<CurrencyPreferencesSnapshot> getSnapshot() async {
    final allowedPref = await _preferences.getByKey(kAllowedCurrenciesPrefKey);
    final defaultPref = await _preferences.getByKey(kDefaultCurrencyPrefKey);

    return buildCurrencyPreferencesSnapshot(
      allowedRaw: allowedPref?.prefValue,
      defaultRaw: defaultPref?.prefValue,
    );
  }
}
