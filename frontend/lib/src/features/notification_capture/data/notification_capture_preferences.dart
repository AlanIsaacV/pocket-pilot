// ============================================================
// NotificationCapturePreferences — toggles del feature de captura
// ============================================================
//
// Persiste dos preferencias device-local. Reutiliza la tabla
// `user_preferences` existente vía UserPreferenceLocalStore, pero NO encola
// push al outbox: las keys se quedan en este device. Razón: la decisión de
// privacidad sobre enviar notificaciones bancarias al LLM debe ser por
// dispositivo, no compartida automáticamente entre el celular y la tablet
// del mismo usuario.
//
// Claves:
//   notification_capture.share_with_llm_for_parser  (default "false")
//      Habilita el fallback al backend cuando ningún parser local matchea.
//      Si está OFF, las notis no parseables quedan unparseable y nunca se
//      envían.
//   notification_capture.help_improve_app           (default "true")
//      Permite que las notificaciones procesadas por el LLM (sin user_id) se
//      retengan en candidate_parsers para mejorar parsers globales. Solo
//      aplica cuando share_with_llm_for_parser está ON. Servirá como
//      consentimiento paraguas para telemetría futura.

import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/user_preference.dart';

const String kPrefShareWithLlmForParser = 'notification_capture.share_with_llm_for_parser';
const String kPrefHelpImproveApp = 'notification_capture.help_improve_app';
const String kPrefLastPurgeAt = 'notification_capture.last_purge_at';

class NotificationCapturePreferences {
  final UserPreferenceLocalStore _store;

  const NotificationCapturePreferences({required UserPreferenceLocalStore store})
      : _store = store;

  Future<bool> shareWithLlmForParser() async {
    final pref = await _store.getByKey(kPrefShareWithLlmForParser);
    return _parseBool(pref?.prefValue, defaultValue: false);
  }

  Future<bool> helpImproveApp() async {
    final pref = await _store.getByKey(kPrefHelpImproveApp);
    return _parseBool(pref?.prefValue, defaultValue: true);
  }

  Future<void> setShareWithLlmForParser(bool value) =>
      _setBool(kPrefShareWithLlmForParser, value);

  Future<void> setHelpImproveApp(bool value) =>
      _setBool(kPrefHelpImproveApp, value);

  /// Última vez que el sweeper de retención (90d) corrió. NULL = nunca.
  /// El sweeper consulta este valor para evitar correr más de una vez por día.
  Future<DateTime?> lastPurgeAt() async {
    final pref = await _store.getByKey(kPrefLastPurgeAt);
    final raw = pref?.prefValue;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastPurgeAt(DateTime value) async {
    final now = DateTime.now().toUtc();
    final existing = await _store.getByKey(kPrefLastPurgeAt);
    final model = UserPreferenceModel(
      prefKey: kPrefLastPurgeAt,
      prefValue: value.toUtc().toIso8601String(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.upsert(model);
    // device-local; no outbox.
  }

  Future<void> _setBool(String key, bool value) async {
    final now = DateTime.now().toUtc();
    final existing = await _store.getByKey(key);
    final model = UserPreferenceModel(
      prefKey: key,
      prefValue: value ? 'true' : 'false',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.upsert(model);
    // Nota: NO llamamos al outbox a propósito — esta key es device-local.
  }

  bool _parseBool(String? raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    return raw == 'true' || raw == '1';
  }
}
