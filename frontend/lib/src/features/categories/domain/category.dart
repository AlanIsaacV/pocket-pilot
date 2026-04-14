import 'package:pocket_pilot/src/generated/pocket_pilot/v1/category_service.pbgrpc.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

class CategoryModel {
  final String id;
  final String name;
  final String icon;
  final String color;
  final String? parentId;

  /// Tipo de categoría: 'income' (ingreso) o 'expense' (gasto).
  final String type;

  /// Naturaleza financiera por defecto para transacciones de esta categoría.
  final String defaultNature;

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
    this.defaultNature = '',
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
      defaultNature: _financialNatureToString(proto.defaultNature),
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
      defaultNature: map['default_nature'] as String? ?? '',
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
      'default_nature': defaultNature,
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
    String? defaultNature,
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
      defaultNature: defaultNature ?? this.defaultNature,
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

  static String _financialNatureToString(FinancialNature nature) {
    switch (nature) {
      case FinancialNature.NATURE_REQUIRED:
        return 'required';
      case FinancialNature.NATURE_OBLIGATION:
        return 'obligation';
      case FinancialNature.NATURE_LIFESTYLE:
        return 'lifestyle';
      case FinancialNature.NATURE_ACTIVE:
        return 'active';
      case FinancialNature.NATURE_PASSIVE:
        return 'passive';
      case FinancialNature.NATURE_WINDFALL:
        return 'windfall';
      case FinancialNature.NATURE_ADJUSTMENT:
        return 'adjustment';
      default:
        return '';
    }
  }

  static FinancialNature stringToFinancialNature(String s) {
    switch (s) {
      case 'required':
        return FinancialNature.NATURE_REQUIRED;
      case 'obligation':
        return FinancialNature.NATURE_OBLIGATION;
      case 'lifestyle':
        return FinancialNature.NATURE_LIFESTYLE;
      case 'active':
        return FinancialNature.NATURE_ACTIVE;
      case 'passive':
        return FinancialNature.NATURE_PASSIVE;
      case 'windfall':
        return FinancialNature.NATURE_WINDFALL;
      case 'adjustment':
        return FinancialNature.NATURE_ADJUSTMENT;
      default:
        return FinancialNature.NATURE_UNSPECIFIED;
    }
  }
}
