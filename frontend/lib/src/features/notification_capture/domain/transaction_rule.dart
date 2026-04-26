// ============================================================
// TransactionRuleModel — substring → categoría
// ============================================================
//
// Sincronizable. Aplica match case-insensitive de `matchText` dentro de la
// description de transacciones que se están creando (notification capture,
// CSV import, AI tools).

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_rule_service.pb.dart';

class TransactionRuleModel {
  final String id;
  final String matchText;
  final String categoryId;
  final int priority;
  final int matchCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;

  const TransactionRuleModel({
    required this.id,
    required this.matchText,
    required this.categoryId,
    required this.priority,
    required this.matchCount,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory TransactionRuleModel.fromProto(TransactionRule proto) {
    return TransactionRuleModel(
      id: proto.id,
      matchText: proto.matchText,
      categoryId: proto.categoryId,
      priority: proto.priority,
      matchCount: proto.matchCount,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory TransactionRuleModel.fromMap(Map<String, dynamic> map) {
    return TransactionRuleModel(
      id: map['id'] as String,
      matchText: map['match_text'] as String,
      categoryId: map['category_id'] as String,
      priority: (map['priority'] as int?) ?? 0,
      matchCount: (map['match_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'match_text': matchText,
        'category_id': categoryId,
        'priority': priority,
        'match_count': matchCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  Map<String, dynamic> toServerMap() => toMap();

  TransactionRuleModel copyWith({
    String? matchText,
    String? categoryId,
    int? priority,
    int? matchCount,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return TransactionRuleModel(
      id: id,
      matchText: matchText ?? this.matchText,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      matchCount: matchCount ?? this.matchCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
