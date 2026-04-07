import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class TemplateTool {
  final DatabaseHelper _db;
  final TransactionRepository _transactionRepo;

  TemplateTool({
    required DatabaseHelper db,
    required TransactionRepository transactionRepo,
  }) : _db = db,
       _transactionRepo = transactionRepo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final templateName = args['template_name'] as String;

      final db = await _db.database;
      final rows = await db.query(
        'transaction_templates',
        where: 'deleted_at IS NULL AND name LIKE ? COLLATE NOCASE',
        whereArgs: ['%$templateName%'],
        orderBy: 'name ASC',
        limit: 5,
      );

      if (rows.isEmpty) {
        final allRows = await db.query(
          'transaction_templates',
          columns: ['name'],
          where: 'deleted_at IS NULL',
          orderBy: 'name ASC',
          limit: 20,
        );
        final names = allRows
            .map((r) => (r['name'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        return AIToolResult(
          success: false,
          content: jsonEncode({
            'error': 'No se encontro una plantilla con ese nombre',
            'available_templates': names,
          }),
        );
      }

      final template = TransactionTemplateModel.fromMap(rows.first);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      if (template.type == 'transfer_out' && template.toAccountId != null) {
        final outId = const Uuid().v4();
        final inId = const Uuid().v4();
        await _transactionRepo.createTransfer(
          outId: outId,
          inId: inId,
          fromAccountId: template.accountId,
          toAccountId: template.toAccountId!,
          amountOutCents: template.amountCents ?? 0,
          currencyOut: template.currencyCode,
          amountInCents: template.amountCents ?? 0,
          currencyIn: template.currencyCode,
          date: date,
          descriptionOut: template.name,
          descriptionIn: template.name,
          tags: template.tags,
        );
        return AIToolResult(
          success: true,
          content: jsonEncode({
            'message':
                'Transferencia creada desde plantilla "${template.name}"',
            'out_id': outId,
            'in_id': inId,
          }),
        );
      }

      final id = const Uuid().v4();
      await _transactionRepo.createTransaction(
        id: id,
        accountId: template.accountId,
        categoryId: template.categoryId,
        templateId: template.id,
        amountMinor: template.amountCents ?? 0,
        currencyCode: template.currencyCode,
        description: template.name,
        date: date,
        type: template.type,
        status: 'cleared',
        tags: template.tags,
      );

      return AIToolResult(
        success: true,
        content: jsonEncode({
          'message': 'Transaccion creada desde plantilla "${template.name}"',
          'id': id,
        }),
      );
    } catch (e) {
      dev.log('TemplateTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al ejecutar plantilla: $e'}),
      );
    }
  }
}
