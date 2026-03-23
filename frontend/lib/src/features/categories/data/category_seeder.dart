import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategorySeeder {
  final CategoryLocalStore _local;
  final DatabaseHelper _db;

  static const _uuid = Uuid();

  CategorySeeder({
    required CategoryLocalStore local,
    required DatabaseHelper db,
  })  : _local = local,
        _db = db;

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
      final entry = node as Map<String, dynamic>;
      final parentId = _uuid.v4();
      final parentType = entry['type'] as String;

      models.add(CategoryModel(
        id: parentId,
        name: entry['name'] as String,
        type: parentType,
        icon: entry['icon'] as String? ?? '',
        color: entry['color'] as String? ?? '',
        createdAt: now,
        updatedAt: now,
      ));

      final parentColor = entry['color'] as String? ?? '';
      final children = entry['children'] as List<dynamic>? ?? [];
      for (final child in children) {
        final c = child as Map<String, dynamic>;
        models.add(CategoryModel(
          id: _uuid.v4(),
          name: c['name'] as String,
          // Los hijos heredan tipo y color del padre si no los especifican.
          type: c['type'] as String? ?? parentType,
          icon: c['icon'] as String? ?? '',
          color: c['color'] as String? ?? parentColor,
          parentId: parentId,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    return models;
  }
}
