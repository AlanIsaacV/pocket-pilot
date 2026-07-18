// ============================================================
// PendingSuggestionsViewModel — sugerencias de notificaciones
// ============================================================
//
// Mantiene la lista de PendingTransactions activas (sugerencias listas para
// aprobar/editar) y dispara `processInbox` antes de cada refresh para que
// nuevas sugerencias aparezcan inmediatamente.
//
// Las raw notifications (status='received'/'unparseable') siguen guardándose
// en SQLite pero ya no se exponen aquí: el sweeper de retención las purga a
// los 90 días y el botón "Reintentar parseo" en Ajustes vuelve a correr el
// engine sobre las unparseables sin necesidad de mostrarlas.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_permission_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';

class PendingSuggestionsViewModel extends ChangeNotifier {
  final PendingTransactionLocalStore _pending;
  final NotificationCaptureRepository _repository;
  final NotificationPermissionService _permission;

  List<PendingTransactionModel> pendingTransactions = [];
  bool isLoading = false;
  bool permissionGranted = false;
  bool _disposed = false;

  PendingSuggestionsViewModel({
    required PendingTransactionLocalStore pending,
    required NotificationCaptureRepository repository,
    required NotificationPermissionService permission,
  }) : _pending = pending,
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
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  Future<void> openPermissionSettings() async {
    await _permission.openSettings();
  }

  /// Reintenta el match local sobre las notificaciones que estaban en
  /// `unparseable`. Útil cuando el parser se actualizó (bump server-side de
  /// la definición). Devuelve cuántas se reabrieron y cuántas matchearon.
  Future<({int reopened, int matched})> reprocessUnparseable() async {
    isLoading = true;
    _safeNotify();
    try {
      final result = await _repository.reprocessUnparseable();
      pendingTransactions = await _pending.listPending();
      return result;
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  Future<void> dismissPending(
    PendingTransactionModel pending, {
    bool? wasHelpful,
  }) async {
    await _repository.dismiss(pending, wasHelpful: wasHelpful);
    pendingTransactions = pendingTransactions
        .where((p) => p.id != pending.id)
        .toList();
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
    bool? wasHelpful,
  }) async {
    final (resolvedBankId, _) = PendingTransactionModel.splitParserId(
      pending.parserId,
    );
    await _repository.approve(
      pending: pending,
      accountId: accountId,
      bankId: bankId ?? resolvedBankId,
      categoryId: categoryId,
      amountCentsOverride: amountCentsOverride,
      currencyCodeOverride: currencyCodeOverride,
      descriptionOverride: descriptionOverride,
      dateOverride: dateOverride,
      wasHelpful: wasHelpful,
    );
    pendingTransactions = pendingTransactions
        .where((p) => p.id != pending.id)
        .toList();
    _safeNotify();
  }

  Future<({int approved, int failed})> approveAllResolved() async {
    final result = await _repository.approveAllResolved();
    pendingTransactions = await _pending.listPending();
    _safeNotify();
    return result;
  }

  Future<List<String>> candidateCategoriesFor(
    PendingTransactionModel pending,
  ) => _repository.candidateCategoriesFor(pending);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
