import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAndroidNotificationsPlugin fakeAndroid;

  setUp(() {
    fakeAndroid = _FakeAndroidNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = fakeAndroid;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'posts a summary and caps actionable suggestions with stable payloads',
    () async {
      final pending = List.generate(6, (index) => _pending('pending-$index'));
      final service = CaptureNotificationService(
        plugin: FlutterLocalNotificationsPlugin(),
        isAndroid: () => true,
      );

      await service.postForRun(
        ProcessInboxResult(
          autoConfirmed: 2,
          leftPending: pending.length,
          leftPendingTransactions: pending,
        ),
        candidateCategoriesFor: (_) async => [
          '11111111-1111-4111-8111-111111111111',
          '22222222-2222-4222-8222-222222222222',
          '33333333-3333-4333-8333-333333333333',
          '44444444-4444-4444-8444-444444444444',
        ],
        categoryNameForId: (id) async => {
          '11111111-1111-4111-8111-111111111111': 'Comida',
          '22222222-2222-4222-8222-222222222222': 'Transporte',
          '33333333-3333-4333-8333-333333333333': 'Servicios',
        }[id],
      );

      expect(fakeAndroid.notifications, hasLength(6));
      final summary = fakeAndroid.notifications.first;
      expect(summary.title, '2 transacciones registradas automáticamente');
      expect(summary.payload, isNull);

      final actionable = fakeAndroid.notifications.skip(1).toList();
      expect(
        actionable,
        hasLength(CaptureNotificationService.maxActionableNotifications),
      );
      for (var index = 0; index < actionable.length; index++) {
        final notification = actionable[index];
        expect(notification.payload, 'pending-$index');
        expect(
          notification.id,
          CaptureNotificationService.notificationIdForPending('pending-$index'),
        );
        expect(notification.details!.actions!.map((action) => action.id), [
          'approve:11111111-1111-4111-8111-111111111111',
          'approve:22222222-2222-4222-8222-222222222222',
          'approve:33333333-3333-4333-8333-333333333333',
          'open_review',
        ]);
        expect(notification.details!.actions!.map((action) => action.title), [
          'Comida',
          'Transporte',
          'Servicios',
          'Abrir revisión',
        ]);
      }
    },
  );

  test('posts nothing when the run has no matched transactions', () async {
    final service = CaptureNotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
      isAndroid: () => true,
    );

    await service.postForRun(
      const ProcessInboxResult(autoConfirmed: 0, leftPending: 0),
      candidateCategoriesFor: (_) async => [],
      categoryNameForId: (_) async => null,
    );

    expect(fakeAndroid.notifications, isEmpty);
  });

  test('does not post a summary when only review is needed', () async {
    final service = CaptureNotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
      isAndroid: () => true,
    );

    await service.postForRun(
      ProcessInboxResult(
        autoConfirmed: 0,
        leftPending: 1,
        leftPendingTransactions: [_pending('review-only')],
      ),
      candidateCategoriesFor: (_) async => [],
      categoryNameForId: (_) async => null,
    );

    expect(fakeAndroid.notifications, hasLength(1));
    expect(fakeAndroid.notifications.single.payload, 'review-only');
    expect(
      fakeAndroid.notifications.single.details!.actions!.single.id,
      'open_review',
    );
  });
}

PendingTransactionModel _pending(String id) => PendingTransactionModel(
  id: id,
  suggestedAccountId: 'account-1',
  amountCents: 100,
  currencyCode: 'MXN',
  merchantDescription: 'Comercio',
  transactionType: 'expense',
  occurredAt: DateTime.utc(2026, 7, 18),
  source: 'parser_local',
  status: 'pending',
  createdAt: DateTime.utc(2026, 7, 18),
);

class _PostedNotification {
  const _PostedNotification({
    required this.id,
    required this.title,
    required this.payload,
    required this.details,
  });

  final int id;
  final String? title;
  final String? payload;
  final AndroidNotificationDetails? details;
}

class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  final notifications = <_PostedNotification>[];

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    notifications.add(
      _PostedNotification(
        id: id,
        title: title,
        payload: payload,
        details: notificationDetails,
      ),
    );
  }
}
