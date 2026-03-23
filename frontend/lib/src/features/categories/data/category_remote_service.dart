// ============================================================
// CategoryRemoteService — wrapper delgado de gRPC para categorías
// ============================================================

import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/category_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class CategoryRemoteService {
  late final CategoryServiceClient _client;

  CategoryRemoteService() {
    _client = CategoryServiceClient(GrpcClient.channel);
  }

  /// Lista categorías del usuario. Si [updatedSince] está definido,
  /// solo retorna las modificadas después de ese timestamp.
  Future<ListCategoriesResponse> listCategories(
    String userId, {
    DateTime? updatedSince,
  }) async {
    try {
      final request = ListCategoriesRequest(userId: userId);
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listCategories(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listCategories error: ${e.message}');
    }
  }

  /// Crea o actualiza una categoría en el servidor.
  Future<UpsertCategoryResponse> upsertCategory(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final category = Category(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        type: _stringToCategoryType(map['type'] as String),
        icon: map['icon'] as String? ?? '',
        color: map['color'] as String? ?? '',
        parentId: map['parent_id'] as String? ?? '',
        createdAt: Timestamp.fromDateTime(
            map['created_at'] != null
                ? DateTime.parse(map['created_at'] as String).toUtc()
                : now),
        updatedAt: Timestamp.fromDateTime(
            map['updated_at'] != null
                ? DateTime.parse(map['updated_at'] as String).toUtc()
                : now),
      );
      return await _client.upsertCategory(UpsertCategoryRequest(category: category));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertCategory error: ${e.message}');
    }
  }

  /// Elimina lógicamente una categoría.
  Future<void> deleteCategory({
    required String id,
    required String userId,
    DateTime? deletedAt,
  }) async {
    try {
      await _client.deleteCategory(
        DeleteCategoryRequest(
          id: id,
          userId: userId,
          deletedAt: Timestamp.fromDateTime(
              (deletedAt ?? DateTime.now()).toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteCategory error: ${e.message}');
    }
  }

  static CategoryType _stringToCategoryType(String type) {
    switch (type) {
      case 'income':
        return CategoryType.CATEGORY_TYPE_INCOME;
      case 'expense':
        return CategoryType.CATEGORY_TYPE_EXPENSE;
      default:
        return CategoryType.CATEGORY_TYPE_UNSPECIFIED;
    }
  }
}
