// Tests del ParserEngine contra el schema BBVA MX v2.
//
// Los casos positivos se leen de test_data/bbva_mx_real_notifications.json,
// que contiene notificaciones reales capturadas del device. Los casos
// negativos (ignore patterns, non-bank) viven inline porque no requieren
// una noti real específica.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';
import 'package:pocket_pilot/src/features/notification_capture/engine/parser_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationParserDefinition bbva;
  late List<Map<String, dynamic>> realFixtures;
  final engine = ParserEngine();

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/parsers/bbva_mx.json');
    bbva = NotificationParserDefinition.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final fixtureFile = File('test_data/bbva_mx_real_notifications.json');
    final fixtureRaw = await fixtureFile.readAsString();
    final fixtureJson = jsonDecode(fixtureRaw) as Map<String, dynamic>;
    realFixtures = (fixtureJson['fixtures'] as List)
        .cast<Map<String, dynamic>>();
  });

  CapturedNotificationModel buildNotification({
    String? title,
    String? text,
    String? bigText,
    String packageName = 'com.bancomer.mbanking',
  }) {
    return CapturedNotificationModel(
      id: 'test',
      packageName: packageName,
      title: title,
      text: text,
      bigText: bigText,
      postedAt: DateTime.utc(2026, 4, 25, 10, 0),
      status: 'received',
      createdAt: DateTime.utc(2026, 4, 25, 10, 0),
    );
  }

  CapturedNotificationModel fromFixture(Map<String, dynamic> f) {
    return CapturedNotificationModel(
      id: f['name'] as String,
      packageName: f['package_name'] as String,
      title: f['title'] as String?,
      text: f['text'] as String?,
      bigText: f['big_text'] as String?,
      postedAt: DateTime.parse(f['posted_at'] as String).toUtc(),
      status: 'received',
      createdAt: DateTime.parse(f['posted_at'] as String).toUtc(),
    );
  }

  group('BBVA MX v2 — real fixtures', () {
    test('every fixture matches with expected fields', () {
      expect(realFixtures, isNotEmpty,
          reason: 'fixture file empty — run dump_captured_notifications.sh');

      for (final f in realFixtures) {
        final name = f['name'] as String;
        final expected = f['expected'] as Map<String, dynamic>;
        final notif = fromFixture(f);

        final match = engine.tryMatch(notif, bbva);

        if (expected['matched'] == false) {
          expect(match, isNull, reason: '$name should not match');
          continue;
        }

        expect(match, isNotNull, reason: '$name should match but did not');
        expect(match!.pattern.id, expected['pattern_id'],
            reason: '$name pattern_id mismatch');
        expect(match.transactionType, expected['transaction_type'],
            reason: '$name transaction_type mismatch');

        final fields = expected['fields'] as Map<String, dynamic>;
        expect(match.amountCents, fields['amount_cents'],
            reason: '$name amount_cents mismatch');
        expect(match.currencyCode, fields['currency_code'],
            reason: '$name currency_code mismatch');
        expect(match.merchantDescription, fields['merchant_description'],
            reason: '$name merchant_description mismatch');
        expect(match.cardLastDigits, fields['card_last_digits'],
            reason: '$name card_last_digits mismatch');
      }
    });
  });

  group('BBVA MX v2 — negative cases', () {
    test('ignores OTP / security code notifications', () {
      final notif = buildNotification(
        title: 'Verificación de identidad',
        text: 'Tu código de seguridad es 123456. No lo compartas.',
      );
      expect(engine.tryMatch(notif, bbva), isNull);
    });

    test('ignores promotional notifications', () {
      final notif = buildNotification(
        title: 'Promoción exclusiva',
        text: '¡Aprovecha 6 MSI en electrónica!',
      );
      expect(engine.tryMatch(notif, bbva), isNull);
    });

    test('returns null for non-bank package', () {
      final notif = buildNotification(
        text: 'Cargo a tu cuenta *5414 de \$100.00',
        packageName: 'com.example.other',
      );
      expect(engine.tryMatch(notif, bbva), isNull);
    });

    test('returns null when text has no recognizable pattern', () {
      final notif = buildNotification(
        title: 'BBVA',
        text: 'Hola, este es un mensaje sin formato de transacción',
      );
      expect(engine.tryMatch(notif, bbva), isNull);
    });
  });
}
