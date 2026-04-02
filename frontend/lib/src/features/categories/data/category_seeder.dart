import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/ids/deterministic_namespace.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';

class CategorySeeder {
  final CategoryLocalStore _local;
  final DatabaseHelper _db;
  final SyncOutbox _outbox;
  final String _userId;

  static const _uuid = Uuid();

  CategorySeeder({
    required CategoryLocalStore local,
    required DatabaseHelper db,
    required SyncOutbox outbox,
    required String userId,
  })  : _local = local,
        _db = db,
        _outbox = outbox,
        _userId = userId;

  /// Inserta las categorías por defecto si no se ha hecho antes.
  /// Lee la definición desde assets/categories/defaults.json.
  /// Los IDs se derivan de forma determinista:
  ///   UUIDv5(kDeterministicCategoryDefaultsNamespace, "$userId/$canonicalId")
  /// donde canonicalId es el UUID fijo definido en el JSON.
  /// Para un mismo usuario, los IDs serán siempre los mismos en cualquier dispositivo.
  Future<void> seedIfNeeded() async {
    final db = await _db.database;

    // Count-based guard: skip seeding if any active categories already exist.
    // This handles both "already seeded on this device" and "pulled from server".
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM categories WHERE deleted_at IS NULL',
    );
    final count = (result.first['cnt'] as int?) ?? 0;
    if (count > 0) return;

    final models = await _loadFromAsset();
    for (final model in models) {
      await _local.upsert(model);
    }

    for (final model in models) {
      await _outbox.enqueue(
        entityType: 'category',
        entityId: model.id,
        operation: 'upsert',
        payload: jsonEncode(model.toServerMap()),
      );
    }

    await db.insert(
      'app_metadata',
      {'key': 'categories_seeded', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Carga y aplana el árbol JSON → lista plana de CategoryModel.
  /// Los padres siempre preceden a sus hijos.
  Future<List<CategoryModel>> _loadFromAsset() async {
    final json = await rootBundle.loadString('assets/categories/defaults.json');
    final list = jsonDecode(json) as List<dynamic>;
    final now = DateTime.now().toUtc();

    final models = <CategoryModel>[];

    for (final node in list) {
      _flattenNode(
        node: node as Map<String, dynamic>,
        parentId: null,
        inheritedType: null,
        inheritedColor: '',
        now: now,
        models: models,
      );
    }

    return models;
  }

  /// Aplana recursivamente un nodo del árbol JSON en CategoryModels.
  /// Pre-order traversal: padres siempre preceden a sus hijos.
  /// El ID se deriva como UUIDv5(kDeterministicCategoryDefaultsNamespace, "$userId/$canonicalId")
  /// donde canonicalId es el campo "id" del JSON — estable entre versiones de la app.
  void _flattenNode({
    required Map<String, dynamic> node,
    required String? parentId,
    required String? inheritedType,
    required String inheritedColor,
    required DateTime now,
    required List<CategoryModel> models,
  }) {
    final canonicalId = node['id'] as String;
    final id = _uuid.v5(kDeterministicCategoryDefaultsNamespace, '$_userId/$canonicalId');
    final type = node['type'] as String? ?? inheritedType!;
    final rawColor = node['color'] as String? ?? inheritedColor;
    final color = rawColor.replaceAll('#', '');

    models.add(CategoryModel(
      id: id,
      name: node['name'] as String,
      type: type,
      icon: CategoryIconData.resolveIcon(node['icon'] as String? ?? ''),
      color: color,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    ));

    final children = node['children'] as List<dynamic>? ?? [];
    for (final child in children) {
      _flattenNode(
        node: child as Map<String, dynamic>,
        parentId: id,
        inheritedType: type,
        inheritedColor: color,
        now: now,
        models: models,
      );
    }
  }
}
