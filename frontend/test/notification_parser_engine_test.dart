// Tests del ParserEngine contra el schema BBVA MX v1.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';
import 'package:pocket_pilot/src/features/notification_capture/engine/parser_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationParserDefinition bbva;
  final engine = ParserEngine();

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/parsers/bbva_mx.json');
    bbva = NotificationParserDefinition.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  });

  CapturedNotificationModel buildNotification({
    String? title,
    String? text,
    String? bigText,
    String packageName = 'com.bbva.bancomermovil',
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

  group('BBVA MX parser', () {
    test('matches credit card purchase with card last digits', () {
      final notif = buildNotification(
        title: 'Cargo aprobado',
        text:
            'Cargo aprobado por \$1,234.56 MXN en STARBUCKS, tarjeta term. 4321',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNotNull);
      expect(match!.amountCents, 123456);
      expect(match.currencyCode, 'MXN');
      expect(match.merchantDescription, 'STARBUCKS');
      expect(match.cardLastDigits, '4321');
      expect(match.transactionType, 'expense');
    });

    test('matches incoming transfer', () {
      final notif = buildNotification(
        text: 'Recibiste \$500.00 MXN de Alan Vazquez. Concepto: Pago',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNotNull);
      expect(match!.amountCents, 50000);
      expect(match.currencyCode, 'MXN');
      expect(match.merchantDescription, 'Alan Vazquez');
      expect(match.transactionType, 'income');
    });

    test('matches online purchase in foreign currency', () {
      final notif = buildNotification(
        text: 'Compra en línea por \$89.99 USD en NETFLIX.COM',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNotNull);
      expect(match!.amountCents, 8999);
      expect(match.currencyCode, 'USD');
      expect(match.merchantDescription, 'NETFLIX.COM');
      expect(match.transactionType, 'expense');
    });

    test('ignores OTP / security code notifications', () {
      final notif = buildNotification(
        title: 'Verificación de identidad',
        text: 'Tu código de seguridad es 123456. No lo compartas.',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNull);
    });

    test('ignores promotional notifications', () {
      final notif = buildNotification(
        title: 'Promoción exclusiva',
        text: '¡Aprovecha 6 MSI en electrónica!',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNull);
    });

    test('returns null for non-bank package', () {
      final notif = buildNotification(
        text: 'Cargo aprobado por \$100.00 MXN en STORE, tarjeta term. 1234',
        packageName: 'com.example.other',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNull);
    });

    test('falls back to default currency when missing in text', () {
      final notif = buildNotification(
        text: 'Recibiste \$250.00 de Juan Pérez',
      );
      final match = engine.tryMatch(notif, bbva);
      expect(match, isNotNull);
      expect(match!.currencyCode, 'MXN');
    });
  });
}
