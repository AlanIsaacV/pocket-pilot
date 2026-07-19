const captureNotificationChannelId = 'pocket_pilot_capture';
const captureSummaryNotificationId = 0x504350;

/// Stable across isolates so a later action handler can cancel the same ID.
int captureNotificationIdForPending(String pendingId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in pendingId.codeUnits) {
    hash = (hash ^ codeUnit) * 0x01000193;
    hash &= 0x7fffffff;
  }
  return hash;
}
