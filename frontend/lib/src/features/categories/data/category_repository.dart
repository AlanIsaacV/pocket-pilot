// ============================================================
// CategoryRepository — orquestación offline-first para categorías
// ============================================================
//
// Patrón outbox: escribe en SQLite local de forma inmediata y encola
// la operación en sync_outbox para que SyncService la envíe al servidor.

import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoryRepository {
  final CategoryLocalStore _local;
  final SyncOutbox _outbox;

  CategoryRepository({
    required CategoryLocalStore local,
    required SyncOutbox outbox,
  })  : _local = local,
        _outbox = outbox;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  Future<List<CategoryModel>> getCategories() => _local.getCategories();

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  Future<void> createCategory({
    required String id,
    required String name,
    required String type,
    String? icon,
    String? color,
    String? parentId,
  }) async {
    final now = DateTime.now().toUtc();
    final model = CategoryModel(
      id: id,
      name: name,
      type: type,
      icon: icon ?? '',
      color: color ?? '',
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );

    await _local.upsert(model);
    await _outbox.enqueue(
      entityType: 'category',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> deleteCategory(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'category',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
