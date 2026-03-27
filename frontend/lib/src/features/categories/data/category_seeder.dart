import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_icon_data.dart';

class CategorySeeder {
  final CategoryLocalStore _local;
  final DatabaseHelper _db;
  final SyncOutbox _outbox;

  static const _uuid = Uuid();

  CategorySeeder({
    required CategoryLocalStore local,
    required DatabaseHelper db,
    required SyncOutbox outbox,
  })  : _local = local,
        _db = db,
        _outbox = outbox;

  /// Inserta las categorías por defecto si no se ha hecho antes.
  /// Lee la definición desde assets/categories/defaults.json.
  /// Los UUIDs e timestamps se generan aquí — el JSON solo lleva nombre,
  /// tipo, icono y color.
  Future<void> seedIfNeeded() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: ['categories_seeded'],
    );
    if (rows.isNotEmpty) return;

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

    await db.insert('app_metadata', {'key': 'categories_seeded', 'value': '1'});
  }

  /// Carga y aplana el árbol JSON → lista plana de CategoryModel con UUIDs.
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
  void _flattenNode({
    required Map<String, dynamic> node,
    required String? parentId,
    required String? inheritedType,
    required String inheritedColor,
    required DateTime now,
    required List<CategoryModel> models,
  }) {
    final id = _uuid.v4();
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
