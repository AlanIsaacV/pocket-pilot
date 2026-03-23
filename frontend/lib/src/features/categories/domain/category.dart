// ============================================================
// Modelo de dominio: Categoría
// ============================================================

// pbgrpc re-exporta category_service.pb.dart (Category) y pbenum.dart (CategoryType).
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/category_service.pbgrpc.dart';

class CategoryModel {
  final String id;
  final String name;

  /// Tipo de categoría: 'income' (ingreso) o 'expense' (gasto).
  final String type;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  factory CategoryModel.fromProto(Category proto) {
    return CategoryModel(
      id: proto.id,
      name: proto.name,
      type: _categoryTypeToString(proto.type),
      createdAt: proto.createdAt.toDateTime(),
      updatedAt: proto.updatedAt.toDateTime(),
    );
  }

  // ----------------------------------------------------------
  // Factory: desde fila SQLite (Map<String, dynamic>)
  // ----------------------------------------------------------
  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // ----------------------------------------------------------
  // Serialización: hacia SQLite
  // ----------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  /// true si esta categoría es de tipo gasto.
  bool get isExpense => type == 'expense';

  /// true si esta categoría es de tipo ingreso.
  bool get isIncome => type == 'income';

  // ----------------------------------------------------------
  // Conversión interna
  // ----------------------------------------------------------
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

  /// Convierte nuestro string de tipo al enum proto para enviar al servidor.
  static CategoryType stringToProtoType(String type) {
    return type == 'income'
        ? CategoryType.CATEGORY_TYPE_INCOME
        : CategoryType.CATEGORY_TYPE_EXPENSE;
  }
}
