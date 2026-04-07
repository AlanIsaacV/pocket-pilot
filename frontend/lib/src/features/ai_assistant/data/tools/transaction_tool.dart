import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:uuid/uuid.dart';

class TransactionTool {
  final TransactionRepository _repo;

  TransactionTool({required TransactionRepository repo}) : _repo = repo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final type = args['type'] as String;
      final accountId = args['account_id'] as String;
      final amountCents = (args['amount_cents'] as num).toInt();
      final currencyCode = args['currency_code'] as String;
      final date = args['date'] as String;
      final description = args['description'] as String? ?? '';
      final categoryId = args['category_id'] as String?;

      if (type == 'transfer_out') {
        final toAccountId = args['to_account_id'] as String?;
        if (toAccountId == null || toAccountId.isEmpty) {
          return const AIToolResult(
            success: false,
            content:
                '{"error": "to_account_id es requerido para transferencias"}',
          );
        }

        final outId = const Uuid().v4();
        final inId = const Uuid().v4();

        await _repo.createTransfer(
          outId: outId,
          inId: inId,
          fromAccountId: accountId,
          toAccountId: toAccountId,
          amountOutCents: amountCents,
          currencyOut: currencyCode,
          amountInCents: amountCents,
          currencyIn: currencyCode,
          date: date,
          descriptionOut: description,
          descriptionIn: description,
          tags: const [],
        );

        return AIToolResult(
          success: true,
          content: jsonEncode({
            'message': 'Transferencia creada',
            'out_id': outId,
            'in_id': inId,
          }),
        );
      }

      final id = const Uuid().v4();
      await _repo.createTransaction(
        id: id,
        accountId: accountId,
        categoryId: categoryId,
        amountMinor: amountCents,
        currencyCode: currencyCode,
        description: description,
        date: date,
        type: type,
        status: 'cleared',
        tags: const [],
      );

      return AIToolResult(
        success: true,
        content: jsonEncode({'message': 'Transaccion creada', 'id': id}),
      );
    } catch (e) {
      dev.log('TransactionTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al crear transaccion: $e'}),
      );
    }
  }
}
