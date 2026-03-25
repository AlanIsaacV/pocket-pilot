import 'package:pocket_pilot/src/generated/pocket_pilot/v1/category_service.pbgrpc.dart';

class CategoryModel {
  final String id;
  final String name;
  final String icon;
  final String color;
  final String? parentId;

  /// Tipo de categoría: 'income' (ingreso) o 'expense' (gasto).
  final String type;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const CategoryModel({
    required this.id,
    required this.name,
    this.icon = '',
    this.color = '',
    this.parentId,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory CategoryModel.fromProto(Category proto) {
    return CategoryModel(
      id: proto.id,
      name: proto.name,
      icon: proto.icon,
      color: proto.color,
      parentId: proto.parentId.isNotEmpty ? proto.parentId : null,
      type: _categoryTypeToString(proto.type),
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt:
          proto.hasDeletedAt() ? proto.deletedAt.toDateTime().toUtc() : null,
    );
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String? ?? '',
      color: map['color'] as String? ?? '',
      parentId: map['parent_id'] as String?,
      type: map['type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  /// Serialización hacia SQLite local.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'parent_id': parentId,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Payload para el outbox. No incluye user_id: el servidor lo lee del token.
  Map<String, dynamic> toServerMap() => toMap();

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';

  CategoryModel copyWith({
    String? name,
    String? icon,
    String? color,
    String? type,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return CategoryModel(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      parentId: parentId,
      type: type ?? this.type,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  static String _categoryTypeToString(CategoryType type) {
    switch (type) {
      case CategoryType.CATEGORY_TYPE_INCOME:
        return 'income';
      case CategoryType.CATEGORY_TYPE_EXPENSE:
        return 'expense';
      default:
        return 'expense';
    }
  }

  static CategoryType stringToProtoType(String type) {
    return type == 'income'
        ? CategoryType.CATEGORY_TYPE_INCOME
        : CategoryType.CATEGORY_TYPE_EXPENSE;
  }
}
