/// A projected financial event for the notification center.
///
/// Persisted in the `notifications` table with read/deleted state.
class InAppNotification {
  final String id;
  final String title;
  final String subtitle;
  final DateTime date;

  /// One of: 'CREDIT_CARD', 'SUBSCRIPTION', 'OBLIGATION'.
  final String type;
  final int? amountCents;

  /// ID of the source account or template that generated this notification.
  final String sourceId;

  /// Display name of the source entity, used for OS notification copy only.
  ///
  /// This is intentionally not persisted so the in-app notification center's
  /// stored representation remains unchanged.
  final String sourceName;
  final bool isRead;
  final DateTime? deletedAt;
  final DateTime createdAt;

  const InAppNotification({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.type,
    this.amountCents,
    required this.sourceId,
    this.sourceName = '',
    this.isRead = false,
    this.deletedAt,
    required this.createdAt,
  });

  factory InAppNotification.fromMap(Map<String, dynamic> map) {
    return InAppNotification(
      id: map['id'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      type: map['type'] as String,
      amountCents: map['amount_cents'] as int?,
      sourceId: map['source_id'] as String,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'date': _dateOnly(date),
      'type': type,
      'amount_cents': amountCents,
      'source_id': sourceId,
      'is_read': isRead ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  InAppNotification copyWith({bool? isRead, DateTime? deletedAt}) {
    return InAppNotification(
      id: id,
      title: title,
      subtitle: subtitle,
      date: date,
      type: type,
      amountCents: amountCents,
      sourceId: sourceId,
      sourceName: sourceName,
      isRead: isRead ?? this.isRead,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt,
    );
  }

  static String _dateOnly(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}
