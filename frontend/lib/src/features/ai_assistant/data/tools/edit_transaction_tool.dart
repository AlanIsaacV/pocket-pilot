import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

class EditTransactionTool {
  final TransactionRepository _repo;

  EditTransactionTool({required TransactionRepository repo}) : _repo = repo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final transactionId = args['transaction_id'] as String;

      final existing = await _repo.getTransactionById(transactionId);
      if (existing == null) {
        return const AIToolResult(
          success: false,
          content: '{"error": "Transaccion no encontrada"}',
        );
      }

      // Merge: use provided values or fall back to existing.
      final accountId = args['account_id'] as String? ?? existing.accountId;
      final amountCents =
          args['amount_cents'] != null
              ? (args['amount_cents'] as num).toInt()
              : existing.amount;
      final currencyCode =
          args['currency_code'] as String? ?? existing.currencyCode;
      final date = args['date'] as String? ?? existing.date;
      final type = args['type'] as String? ?? existing.type;
      final description =
          args.containsKey('description')
              ? args['description'] as String? ?? ''
              : existing.description;
      final categoryId =
          args.containsKey('category_id')
              ? args['category_id'] as String?
              : existing.categoryId;
      final tags =
          args.containsKey('tags')
              ? (args['tags'] as List<dynamic>).cast<String>()
              : existing.tags;

      await _repo.updateTransaction(
        id: transactionId,
        accountId: accountId,
        categoryId: categoryId,
        templateId: existing.templateId,
        amountMinor: amountCents,
        installmentsCount: existing.installmentsCount,
        currencyCode: currencyCode,
        description: description,
        date: date,
        type: type,
        status: existing.status,
        tags: tags,
        createdAt: existing.createdAt,
      );

      return AIToolResult(
        success: true,
        content: jsonEncode({
          'message': 'Transaccion actualizada',
          'id': transactionId,
        }),
      );
    } catch (e) {
      dev.log('EditTransactionTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al editar transaccion: $e'}),
      );
    }
  }
}
