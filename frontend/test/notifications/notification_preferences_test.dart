import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/notifications/notification_preferences.dart';

void main() {
  test('defaults reproduce the existing notification schedule', () {
    const preferences = NotificationPreferences.defaults;

    expect(preferences.enabledTypes.values, everyElement(isTrue));
    expect(preferences.notifyHour, 9);
    expect(preferences.notifyMinute, 0);
    expect(preferences.anticipationFor('CREDIT_CARD'), 3);
    expect(preferences.anticipationFor('SUBSCRIPTION'), 1);
    expect(preferences.anticipationFor('OBLIGATION'), 0);
    expect(preferences.anticipationFor('STATEMENT_IMPORT'), 0);
  });

  test('round-trips all notification settings as JSON', () {
    const preferences = NotificationPreferences(
      enabledTypes: {
        'CREDIT_CARD': false,
        'SUBSCRIPTION': true,
        'OBLIGATION': false,
        'STATEMENT_IMPORT': true,
      },
      notifyHour: 17,
      notifyMinute: 45,
      anticipationDays: {
        'CREDIT_CARD': 5,
        'SUBSCRIPTION': 2,
        'OBLIGATION': 1,
        'STATEMENT_IMPORT': 0,
      },
    );

    final decoded = NotificationPreferences.decode(preferences.encode());

    expect(decoded.enabledTypes, preferences.enabledTypes);
    expect(decoded.notifyHour, preferences.notifyHour);
    expect(decoded.notifyMinute, preferences.notifyMinute);
    expect(decoded.anticipationDays, preferences.anticipationDays);
  });

  test(
    'ignores unknown fields and falls back to defaults for malformed data',
    () {
      final unknownFields = NotificationPreferences.decode('''
      {
        "notifyHour": 10,
        "futureSetting": "ignored",
        "enabledTypes": {"CREDIT_CARD": false, "FUTURE_TYPE": "ignored"},
        "anticipationDays": {"CREDIT_CARD": 4, "FUTURE_TYPE": "ignored"}
      }
    ''');
      final malformed = NotificationPreferences.decode('''
      {"enabledTypes": {"CREDIT_CARD": "yes"}}
    ''');

      expect(unknownFields.notifyHour, 10);
      expect(unknownFields.isEnabled('CREDIT_CARD'), isFalse);
      expect(unknownFields.anticipationFor('CREDIT_CARD'), 4);
      expect(
        malformed.enabledTypes,
        NotificationPreferences.defaults.enabledTypes,
      );
      expect(malformed.notifyHour, NotificationPreferences.defaults.notifyHour);
    },
  );
}
