// ============================================================
// BanksPickerViewModel — estado de la pantalla "Mis bancos"
// ============================================================
//
// Estado: lista de packages observados (package_observations) cruzada con
// watched_packages, bank_aliases (per-user sync) y bank_packages (catálogo
// global pull-only). Cada entrada `BanksPickerEntry` resume si el usuario
// ya marcó el package como banco, qué alias asignó, y si el catálogo global
// sugiere un bank_id/label.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/package_observation_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/watched_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/bank_alias.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/bank_package.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/package_observation.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/watched_package.dart';

class BanksPickerEntry {
  final PackageObservationModel observation;
  final WatchedPackageModel? watched;
  final BankAliasModel? alias;
  final BankPackageModel? catalogEntry;

  const BanksPickerEntry({
    required this.observation,
    this.watched,
    this.alias,
    this.catalogEntry,
  });

  String get packageName => observation.packageName;

  /// True si el usuario marcó este package como banco en este device
  /// (watched_packages.enabled = 1).
  bool get isWatched => watched?.enabled ?? false;

  /// True si el usuario asignó un alias en cualquier device (sincroniza).
  /// Útil para mostrar hint "marcaste esto en otro device" cuando
  /// `aliasExists && !isWatched`.
  bool get aliasExists => alias != null;

  /// El nombre amigable a mostrar: alias del usuario > default del catálogo
  /// > package_name como fallback.
  String get displayLabel {
    final aliasLabel = alias?.displayLabel;
    if (aliasLabel != null && aliasLabel.isNotEmpty) return aliasLabel;
    final catalogLabel = catalogEntry?.defaultLabel;
    if (catalogLabel != null && catalogLabel.isNotEmpty) return catalogLabel;
    return packageName;
  }

  String? get suggestedBankId => alias?.bankId ?? catalogEntry?.bankId;
}

class BanksPickerViewModel extends ChangeNotifier {
  static const _uuid = Uuid();

  final PackageObservationLocalStore _observations;
  final WatchedPackageLocalStore _watched;
  final BankAliasLocalStore _aliases;
  final BankPackageLocalStore _bankPackages;
  final BankPackageRemoteService _remote;
  final NotificationCapturePreferences _preferences;
  final SyncOutbox _outbox;

  BanksPickerViewModel({
    required PackageObservationLocalStore observations,
    required WatchedPackageLocalStore watched,
    required BankAliasLocalStore aliases,
    required BankPackageLocalStore bankPackages,
    required BankPackageRemoteService remote,
    required NotificationCapturePreferences preferences,
    required SyncOutbox outbox,
  })  : _observations = observations,
        _watched = watched,
        _aliases = aliases,
        _bankPackages = bankPackages,
        _remote = remote,
        _preferences = preferences,
        _outbox = outbox;

  List<BanksPickerEntry> entries = [];
  bool isLoading = false;
  bool _disposed = false;

  /// Cantidad de entries marcados — útil para el badge "Mis bancos (N)".
  int get watchedCount => entries.where((e) => e.isWatched).length;

  void loadOnAppear() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    isLoading = true;
    _safeNotify();
    try {
      final observations = await _observations.listActive();
      final watchedAll = await _watched.listAll();
      final aliasesAll = await _aliases.listActive();
      final catalogAll = await _bankPackages.listActive();

      final watchedByPkg = {for (final w in watchedAll) w.packageName: w};
      final aliasByPkg = {for (final a in aliasesAll) a.packageName: a};
      final catalogByPkg = {for (final c in catalogAll) c.packageName: c};

      // Unimos packages observados + cualquier watched_package o bank_alias
      // que no haya generado observación todavía (caso edge: BBVA seedeado
      // por mig 016 antes de que llegue una nueva noti).
      final packageNames = <String>{
        ...observations.map((o) => o.packageName),
        ...watchedByPkg.keys,
        ...aliasByPkg.keys,
      };

      final observationsByPkg = {for (final o in observations) o.packageName: o};

      entries = packageNames
          .map((pkg) {
            return BanksPickerEntry(
              observation: observationsByPkg[pkg] ??
                  PackageObservationModel(
                    packageName: pkg,
                    firstSeenAt: DateTime.fromMillisecondsSinceEpoch(0),
                    lastSeenAt: DateTime.fromMillisecondsSinceEpoch(0),
                    notiCount: 0,
                  ),
              watched: watchedByPkg[pkg],
              alias: aliasByPkg[pkg],
              catalogEntry: catalogByPkg[pkg],
            );
          })
          .toList()
        ..sort((a, b) {
          // Watched primero, luego con alias (sync from other device),
          // luego por count desc, luego por last_seen_at desc.
          if (a.isWatched != b.isWatched) return a.isWatched ? -1 : 1;
          if (a.aliasExists != b.aliasExists) return a.aliasExists ? -1 : 1;
          if (a.observation.notiCount != b.observation.notiCount) {
            return b.observation.notiCount.compareTo(a.observation.notiCount);
          }
          return b.observation.lastSeenAt.compareTo(a.observation.lastSeenAt);
        });
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  /// Marca un package como banco. Si ya existía un watched/alias soft-deleted,
  /// los reactiva (LWW). Si el package está en bank_packages global, prefilla
  /// bankId y label sugerido. La sugerencia anónima al backend solo se envía
  /// si `help_improve_app=ON`.
  Future<void> markAsBank({
    required String packageName,
    required String displayLabel,
    String? bankId,
  }) async {
    final now = DateTime.now().toUtc();

    // 1. Watched (per-device, sin outbox).
    final existingWatched = await _watched.getByPackageName(packageName);
    if (existingWatched == null) {
      await _watched.upsert(WatchedPackageModel(
        id: _uuid.v4(),
        packageName: packageName,
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ));
    } else if (!existingWatched.enabled) {
      await _watched.setEnabled(packageName: packageName, enabled: true);
    }

    // 2. Alias (per-user, sync via outbox). Si ya existía aunque
    // soft-deleted, lo reactivamos manteniendo el id (LWW server-side).
    final existingAlias =
        await _aliases.getByPackageNameIncludingDeleted(packageName);
    final aliasModel = existingAlias?.copyWith(
          bankId: bankId,
          displayLabel: displayLabel,
          updatedAt: now,
          clearDeletedAt: true,
        ) ??
        BankAliasModel(
          id: _uuid.v4(),
          packageName: packageName,
          bankId: bankId,
          displayLabel: displayLabel,
          createdAt: now,
          updatedAt: now,
        );
    await _aliases.upsert(aliasModel);
    await _outbox.enqueue(
      entityType: 'bank_alias',
      entityId: aliasModel.id,
      operation: 'upsert',
      payload: jsonEncode(aliasModel.toServerMap()),
    );

    // 3. Sugerencia anónima al backend, gated por help_improve_app. Fire-
    // and-forget — si falla, no afecta la UX.
    final shouldSuggest = await _preferences.helpImproveApp();
    if (shouldSuggest) {
      try {
        await _remote.submitPackageSuggestion(
          packageName: packageName,
          proposedLabel: displayLabel,
          proposedBankId: bankId,
        );
      } catch (e, st) {
        developer.log('submitPackageSuggestion failed: $e',
            name: 'BanksPicker', error: e, stackTrace: st);
      }
    }

    await refresh();
  }

  /// Desmarca un package como banco. Soft-delete del alias y disable del
  /// watched (per-device). El package_observation se mantiene — el log
  /// liviano sigue acumulando si el package vuelve a notificar.
  Future<void> unmarkAsBank(String packageName) async {
    final now = DateTime.now().toUtc();

    await _watched.setEnabled(packageName: packageName, enabled: false);

    final existingAlias =
        await _aliases.getByPackageNameIncludingDeleted(packageName);
    if (existingAlias != null && existingAlias.deletedAt == null) {
      await _aliases.softDelete(existingAlias.id, now);
      await _outbox.enqueue(
        entityType: 'bank_alias',
        entityId: existingAlias.id,
        operation: 'delete',
        payload: jsonEncode({
          'id': existingAlias.id,
          'deleted_at': now.toIso8601String(),
        }),
      );
    }

    await refresh();
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
