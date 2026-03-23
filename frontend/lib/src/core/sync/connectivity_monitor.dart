// ============================================================
// ConnectivityMonitor — trigger automático de sync al reconectar
// ============================================================
//
// Observa el estado de la red usando el paquete connectivity_plus.
// Cuando detecta que el dispositivo recupera conectividad (pasa de
// sin red a cualquier tipo de conexión), lanza un ciclo de sync.
//
// Uso:
//   final monitor = ConnectivityMonitor(syncService: syncService, userId: userId);
//   monitor.startMonitoring(); // llamar una vez al iniciar la app

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';

class ConnectivityMonitor {
  final SyncService _syncService;
  final String _userId;

  bool _wasOffline = false;

  ConnectivityMonitor({
    required SyncService syncService,
    required String userId,
  })  : _syncService = syncService,
        _userId = userId;

  /// Inicia la escucha de cambios de conectividad.
  /// Llama a este método una vez al iniciar la app.
  void startMonitoring() {
    Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  /// Verifica la conectividad actual y lanza un sync si hay conexión.
  Future<void> checkAndSync() async {
    final results = await Connectivity().checkConnectivity();
    final hasConnection = _hasConnection(results);
    if (hasConnection) {
      await _syncService.sync(_userId);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = _hasConnection(results);

    if (hasConnection && _wasOffline) {
      // Recuperó la conexión: lanzar sync inmediatamente.
      _syncService.sync(_userId);
    }

    _wasOffline = !hasConnection;
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
