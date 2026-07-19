import 'dart:convert';

import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

const String kPrefNotificationSettings = 'notifications.settings';

/// Device-local settings that control OS payment reminders.
class NotificationPreferences {
  static const NotificationPreferences defaults = NotificationPreferences();

  final Map<String, bool> enabledTypes;
  final int notifyHour;
  final int notifyMinute;
  final Map<String, int> anticipationDays;

  const NotificationPreferences({
    this.enabledTypes = const {
      'CREDIT_CARD': true,
      'SUBSCRIPTION': true,
      'OBLIGATION': true,
      'STATEMENT_IMPORT': true,
    },
    this.notifyHour = 9,
    this.notifyMinute = 0,
    this.anticipationDays = const {
      'CREDIT_CARD': 3,
      'SUBSCRIPTION': 1,
      'OBLIGATION': 0,
      'STATEMENT_IMPORT': 0,
    },
  });

  bool isEnabled(String type) => enabledTypes[type] ?? false;

  int anticipationFor(String type) => anticipationDays[type] ?? 0;

  Map<String, Object> toJson() => {
    'enabledTypes': enabledTypes,
    'notifyHour': notifyHour,
    'notifyMinute': notifyMinute,
    'anticipationDays': anticipationDays,
  };

  String encode() => jsonEncode(toJson());

  factory NotificationPreferences.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return defaults;

      final enabledTypes = _parseEnabledTypes(decoded['enabledTypes']);
      final notifyHour = _parseHour(decoded['notifyHour']);
      final notifyMinute = _parseMinute(decoded['notifyMinute']);
      final anticipationDays = _parseAnticipationDays(
        decoded['anticipationDays'],
      );
      return NotificationPreferences(
        enabledTypes: enabledTypes,
        notifyHour: notifyHour,
        notifyMinute: notifyMinute,
        anticipationDays: anticipationDays,
      );
    } catch (_) {
      return defaults;
    }
  }

  static Map<String, bool> _parseEnabledTypes(Object? raw) {
    final values = Map<String, bool>.from(defaults.enabledTypes);
    if (raw == null) return values;
    if (raw is! Map) throw const FormatException('enabledTypes must be a map');
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !values.containsKey(key)) continue;
      if (value is! bool) {
        throw const FormatException('invalid enabled type');
      }
      values[key] = value;
    }
    return values;
  }

  static int _parseHour(Object? raw) {
    if (raw == null) return defaults.notifyHour;
    if (raw is! int || raw < 0 || raw > 23) {
      throw const FormatException('invalid notification hour');
    }
    return raw;
  }

  static int _parseMinute(Object? raw) {
    if (raw == null) return defaults.notifyMinute;
    if (raw is! int || raw < 0 || raw > 59) {
      throw const FormatException('invalid notification minute');
    }
    return raw;
  }

  static Map<String, int> _parseAnticipationDays(Object? raw) {
    final values = Map<String, int>.from(defaults.anticipationDays);
    if (raw == null) return values;
    if (raw is! Map) {
      throw const FormatException('anticipationDays must be a map');
    }
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !values.containsKey(key)) continue;
      if (value is! int || value < 0) {
        throw const FormatException('invalid anticipation day');
      }
      values[key] = value;
    }
    return values;
  }
}

/// Reads and writes notification settings without adding them to the sync outbox.
abstract class NotificationPreferencesStore {
  Future<NotificationPreferences> getPreferences();

  Future<void> savePreferences(NotificationPreferences preferences);
}

/// Persists notification settings on this device only.
class NotificationPreferencesLocalStore
    implements NotificationPreferencesStore {
  final UserPreferenceLocalStore _store;

  const NotificationPreferencesLocalStore({
    required UserPreferenceLocalStore store,
  }) : _store = store;

  @override
  Future<NotificationPreferences> getPreferences() async {
    final preference = await _store.getByKey(kPrefNotificationSettings);
    final raw = preference?.prefValue;
    if (raw == null || raw.isEmpty) return NotificationPreferences.defaults;
    return NotificationPreferences.decode(raw);
  }

  @override
  Future<void> savePreferences(NotificationPreferences preferences) async {
    final now = DateTime.now().toUtc();
    final existing = await _store.getByKey(kPrefNotificationSettings);
    await _store.upsert(
      UserPreferenceModel(
        prefKey: kPrefNotificationSettings,
        prefValue: preferences.encode(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}

class DefaultNotificationPreferencesStore
    implements NotificationPreferencesStore {
  const DefaultNotificationPreferencesStore();

  @override
  Future<NotificationPreferences> getPreferences() async =>
      NotificationPreferences.defaults;

  @override
  Future<void> savePreferences(NotificationPreferences preferences) async {}
}
