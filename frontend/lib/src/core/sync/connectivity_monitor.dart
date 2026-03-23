import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:pocket_pilot/src/core/sync/sync_service.dart';

class ConnectivityMonitor {
  final SyncService _syncService;
  bool _wasOffline = false;

  ConnectivityMonitor({required SyncService syncService})
      : _syncService = syncService;

  void startMonitoring() {
    Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  Future<void> checkAndSync() async {
    final results = await Connectivity().checkConnectivity();
    if (_hasConnection(results)) {
      await _syncService.sync();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = _hasConnection(results);
    if (hasConnection && _wasOffline) {
      _syncService.sync();
    }
    _wasOffline = !hasConnection;
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
