// ============================================================
// CategoryRepository — orquestación offline-first para categorías
// ============================================================
//
// Este repositorio no contiene SQL: delega toda persistencia en
// CategoryLocalStore y toda comunicación remota en CategoryRemoteService.

import 'dart:async';

import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_remote_service.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoryRepository {
  final CategoryLocalStore _local;
  final CategoryRemoteService _remote;

  CategoryRepository({
    required CategoryLocalStore local,
    required CategoryRemoteService remote,
  }) : _local = local,
       _remote = remote;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Lee las categorías almacenadas localmente.
  Future<List<CategoryModel>> getCategories(String userId) =>
      _local.getCategories(userId);

  /// Descarga categorías del servidor y las persiste en SQLite.
  /// Propaga errores para que el ViewModel pueda mostrarlos.
  Future<void> syncRemote(String userId) async {
    final response = await _remote.listCategories(userId);
    await _local.upsertAll(
      response.categories.map(CategoryModel.fromProto).toList(),
    );
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Crea una categoría local y luego sincroniza con el servidor.
  Future<void> createCategory({
    required String id,
    required String userId,
    required String name,
    required String type, // 'income' | 'expense'
  }) async {
    final now = DateTime.now().toUtc();

    await _local.upsert(
      CategoryModel(
        id: id,
        name: name,
        type: type,
        createdAt: now,
        updatedAt: now,
      ),
    );

    unawaited(() async {
      try {
        await _remote.upsertCategory({
          'id': id,
          'user_id': userId,
          'name': name,
          'type': type,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      } catch (_) {}
    }());
  }
}
