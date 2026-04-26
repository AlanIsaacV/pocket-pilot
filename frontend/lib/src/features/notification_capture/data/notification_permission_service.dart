// ============================================================
// NotificationPermissionService — wrapper sobre el MethodChannel nativo
// ============================================================
//
// Expone dos operaciones:
//   isPermissionGranted() → ¿el usuario habilitó al BankNotificationListenerService?
//   openSettings()        → abre Ajustes → Acceso a notificaciones del sistema
//
// El permiso `BIND_NOTIFICATION_LISTENER_SERVICE` no se puede pedir con un
// diálogo de runtime: el usuario debe tocar manualmente el toggle en Ajustes.
// El channel está disponible solo en Android; en iOS toda llamada tira false.

import 'dart:io';

import 'package:flutter/services.dart';

class NotificationPermissionService {
  static const _channel = MethodChannel('com.pocketpilot/notification_capture');

  bool get isSupported => Platform.isAndroid;

  Future<bool> isPermissionGranted() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isPermissionGranted');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException {
      // Silencioso: la UI ya muestra estado actual y reintenta al volver.
    }
  }
}
