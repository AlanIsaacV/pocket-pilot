// ============================================================
// NotificationInboxViewModel — estado de la bandeja de notificaciones
// ============================================================
//
// La bandeja muestra dos cosas:
//   - PendingTransactions activas (sugerencias listas para aprobar/editar)
//   - CapturedNotifications raw aún sin procesar o no parseables
//
// Al refrescar, primero corre el engine sobre los `received` para producir
// nuevas sugerencias, luego carga ambas listas para renderizar.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_permission_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';

class NotificationInboxViewModel extends ChangeNotifier {
  final CapturedNotificationLocalStore _captured;
  final PendingTransactionLocalStore _pending;
  final NotificationCaptureRepository _repository;
  final NotificationPermissionService _permission;

  List<PendingTransactionModel> pendingTransactions = [];
  List<CapturedNotificationModel> rawNotifications = [];
  bool isLoading = false;
  bool permissionGranted = false;
  bool _disposed = false;

  NotificationInboxViewModel({
    required CapturedNotificationLocalStore captured,
    required PendingTransactionLocalStore pending,
    required NotificationCaptureRepository repository,
    required NotificationPermissionService permission,
  })  : _captured = captured,
        _pending = pending,
        _repository = repository,
        _permission = permission;

  void loadOnAppear() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    isLoading = true;
    _safeNotify();
    try {
      permissionGranted = await _permission.isPermissionGranted();
      // Run engine over any received notifications first so new pending
      // transactions show up immediately on this refresh.
      await _repository.processInbox();
      pendingTransactions = await _pending.listPending();
      rawNotifications = await _captured.listInbox();
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  Future<void> openPermissionSettings() async {
    await _permission.openSettings();
  }

  Future<void> dismissRaw(String capturedId) async {
    await _captured.updateStatus(capturedId, 'ignored');
    rawNotifications = rawNotifications.where((n) => n.id != capturedId).toList();
    _safeNotify();
  }

  Future<void> dismissPending(PendingTransactionModel pending) async {
    await _repository.dismiss(pending);
    pendingTransactions =
        pendingTransactions.where((p) => p.id != pending.id).toList();
    _safeNotify();
  }

  Future<void> approvePending({
    required PendingTransactionModel pending,
    required String accountId,
    String? bankId,
    String? categoryId,
    int? amountCentsOverride,
    String? currencyCodeOverride,
    String? descriptionOverride,
    DateTime? dateOverride,
  }) async {
    await _repository.approve(
      pending: pending,
      accountId: accountId,
      bankId: bankId ?? _bankIdFromParserId(pending.parserId),
      categoryId: categoryId,
      amountCentsOverride: amountCentsOverride,
      currencyCodeOverride: currencyCodeOverride,
      descriptionOverride: descriptionOverride,
      dateOverride: dateOverride,
    );
    pendingTransactions =
        pendingTransactions.where((p) => p.id != pending.id).toList();
    _safeNotify();
  }

  /// El parser_id se persiste como "bbva_mx/purchase_card"; el bank_id es la
  /// parte antes del slash. Si por alguna razón no viene, devolvemos null y
  /// el aprendizaje de mappings se salta para esa aprobación.
  String? _bankIdFromParserId(String? parserId) {
    if (parserId == null) return null;
    final slash = parserId.indexOf('/');
    if (slash <= 0) return null;
    return parserId.substring(0, slash);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
