// ============================================================
// CategoryLocalStore (DAO) — todas las queries SQLite de categorías
// ============================================================
//
// Responsabilidad única: ejecutar operaciones de base de datos
// sobre la tabla `categories`. No contiene lógica de negocio ni
// llama a servicios remotos.

import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';

class CategoryLocalStore {
  final DatabaseHelper _db;

  CategoryLocalStore({required DatabaseHelper db}) : _db = db;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  /// Retorna todas las categorías activas, ordenadas por fecha de
  /// creación ascendente (las más antiguas primero).
  Future<List<CategoryModel>> getCategories() async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(CategoryModel.fromMap).toList();
  }

  /// Obtiene el tipo ('income'|'expense') de una categoría por su ID.
  /// Devuelve 'expense' por defecto si no se encuentra.
  ///
  /// Usado por TransactionLocalStore para enriquecer los modelos de transacción.
  Future<String> getCategoryType(String categoryId) async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      columns: ['type'],
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first['type'] as String : 'expense';
  }

  /// Retorna todas las categorías ocultas (soft-deleted).
  Future<List<CategoryModel>> getDeletedCategories() async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(CategoryModel.fromMap).toList();
  }

  /// Obtiene una categoría por su ID (activa o eliminada).
  Future<CategoryModel?> getCategoryById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CategoryModel.fromMap(rows.first);
  }

  // ----------------------------------------------------------
  // WRITE
  // ----------------------------------------------------------

  /// Inserta o reemplaza una lista de categorías en un solo batch.
  /// Usado para sincronizar la respuesta del servidor.
  Future<void> upsertAll(List<CategoryModel> categories) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final model in categories) {
      batch.insert(
        'categories',
        model.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Inserta o reemplaza una categoría individual.
  /// Usado para la escritura local inmediata al crear una categoría.
  Future<void> upsert(CategoryModel model) async {
    final db = await _db.database;
    await db.insert(
      'categories',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca una categoría como eliminada (soft delete con LWW).
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final db = await _db.database;
    await db.update(
      'categories',
      {
        'deleted_at': deletedAt.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
      },
      where: 'id = ? AND (deleted_at IS NULL OR deleted_at < ?)',
      whereArgs: [id, deletedAt.toIso8601String()],
    );
  }

  /// Restaura una categoría oculta (quita soft-delete).
  Future<void> restore(String id, DateTime updatedAt) async {
    final db = await _db.database;
    await db.update(
      'categories',
      {
        'deleted_at': null,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
