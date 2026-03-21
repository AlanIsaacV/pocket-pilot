// ============================================================
// CategoryRemoteService — wrapper delgado de gRPC para categorías
// ============================================================

import 'package:grpc/grpc.dart';
// pbgrpc re-exporta pb.dart y pbenum.dart — un solo import cubre todo.
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/category_service.pbgrpc.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class CategoryRemoteService {
  late final CategoryServiceClient _client;

  CategoryRemoteService() {
    _client = CategoryServiceClient(GrpcClient.channel);
  }

  /// Lista todas las categorías del usuario.
  /// Pasa [type] para filtrar por tipo, o usa CATEGORY_TYPE_UNSPECIFIED
  /// para obtener todas.
  Future<List<Category>> listCategories(String userId) async {
    try {
      final response = await _client.listCategories(
        // Sin filtro de tipo → el servidor retorna todas.
        ListCategoriesRequest(userId: userId),
      );
      return response.categories;
    } on GrpcError catch (e) {
      throw Exception('gRPC listCategories error: ${e.message}');
    }
  }

  /// Crea una nueva categoría en el servidor.
  Future<Category> createCategory({
    required String userId,
    required String name,
    required CategoryType type,
  }) async {
    try {
      final response = await _client.createCategory(
        CreateCategoryRequest(
          userId: userId,
          name: name,
          type: type,
        ),
      );
      return response.category;
    } on GrpcError catch (e) {
      throw Exception('gRPC createCategory error: ${e.message}');
    }
  }

  /// Elimina una categoría.
  Future<void> deleteCategory({
    required String userId,
    required String categoryId,
  }) async {
    try {
      await _client.deleteCategory(
        DeleteCategoryRequest(userId: userId, categoryId: categoryId),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteCategory error: ${e.message}');
    }
  }
}
