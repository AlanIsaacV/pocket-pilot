// ============================================================
// ViewModel: Cuentas
// ============================================================
//
// Flujo al entrar a la pantalla (loadOnAppear):
//   1. Lee SQLite local → UI se actualiza inmediatamente (sin red).
//   2. Si pasaron ≥5s desde la última sync exitosa, lanza sync remoto
//      en background → UI se actualiza al terminar.
//
// Estados que expone:
//   isLoading  → true solo si no hay datos locales Y estamos sincronizando.
//                La pantalla muestra un spinner bloqueante.
//   isSyncing  → true mientras corre la sync remota (datos locales visibles).
//                La pantalla muestra un LinearProgressIndicator sutil.
//   errorMessage → mensaje si la sync falla; null si todo va bien.
//                  No borra los datos locales.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountsViewModel extends ChangeNotifier {
  final AccountRepository _repository;

  List<AccountModel> accounts = [];

  /// true = spinner bloqueante (sin datos locales + sincronizando).
  bool isLoading = false;

  /// true = LinearProgressIndicator sutil (datos visibles, sync en curso).
  bool isSyncing = false;

  /// Mensaje del último error de sync. No se limpia con los datos locales.
  String? errorMessage;

  /// Momento de la última sync remota exitosa. Controla el throttle de 5s.
  DateTime? _lastRemoteSyncAt;

  AccountsViewModel({required AccountRepository repository})
      : _repository = repository;

  // ----------------------------------------------------------
  // API pública
  // ----------------------------------------------------------

  /// Llamar al montar la ruta. Carga local inmediatamente,
  /// luego sincroniza remoto si el throttle lo permite.
  ///
  /// Retorna void para que funcione limpio en el cascade del Provider:
  ///   create: (_) => AccountsViewModel(...)..loadOnAppear()
  void loadOnAppear() {
    unawaited(_loadLocalThenMaybeSync());
  }

  /// Llamar desde RefreshIndicator. Siempre fuerza sync remoto,
  /// ignorando el throttle.
  Future<void> refresh() => _syncRemote();

  // ----------------------------------------------------------
  // Implementación interna
  // ----------------------------------------------------------

  Future<void> _loadLocalThenMaybeSync() async {
    // Paso 1: datos locales → UI actualizada sin esperar red.
    accounts = await _repository.getAccounts(kHardcodedUserId);
    notifyListeners();

    // Paso 2: sync remota si el throttle lo permite.
    await _maybeSyncRemote();
  }

  Future<void> _maybeSyncRemote() async {
    final last = _lastRemoteSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 5)) {
      return; // sync reciente: no volver a llamar al servidor
    }
    await _syncRemote();
  }

  Future<void> _syncRemote() async {
    // isLoading solo si no hay nada que mostrar todavía.
    isLoading = accounts.isEmpty;
    isSyncing = true;
    notifyListeners();

    try {
      await _repository.syncRemote(kHardcodedUserId);
      accounts = await _repository.getAccounts(kHardcodedUserId);
      _lastRemoteSyncAt = DateTime.now();
      errorMessage = null;
    } catch (e) {
      // La sync falló: mantenemos los datos locales que ya teníamos.
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      isSyncing = false;
      notifyListeners();
    }
  }
}
