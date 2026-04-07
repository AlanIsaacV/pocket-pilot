import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/financial_summary_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/goal_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/template_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/edit_transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/unsupported_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';

class AIToolDispatcher {
  final TransactionTool _transactionTool;
  final EditTransactionTool _editTransactionTool;
  final TemplateTool _templateTool;
  final FinancialSummaryTool _financialSummaryTool;
  final GoalTool _goalTool;
  final UnsupportedTool _unsupportedTool;

  AIToolDispatcher({
    required TransactionTool transactionTool,
    required EditTransactionTool editTransactionTool,
    required TemplateTool templateTool,
    required FinancialSummaryTool financialSummaryTool,
    required GoalTool goalTool,
    required AIRemoteService remote,
  }) : _transactionTool = transactionTool,
       _editTransactionTool = editTransactionTool,
       _templateTool = templateTool,
       _financialSummaryTool = financialSummaryTool,
       _goalTool = goalTool,
       _unsupportedTool = UnsupportedTool(remote: remote);

  Future<AIToolResult> dispatch(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    switch (toolName) {
      case 'gestionar_transaccion':
        return _transactionTool.execute(arguments);
      case 'editar_transaccion':
        return _editTransactionTool.execute(arguments);
      case 'ejecutar_plantilla':
        return _templateTool.execute(arguments);
      case 'consultar_resumen_financiero':
        return _financialSummaryTool.execute(arguments);
      case 'gestionar_meta':
        return _goalTool.execute(arguments);
      case 'reportar_funcion_no_soportada':
        return _unsupportedTool.execute(arguments);
      default:
        return _unsupportedTool.execute({
          'user_intent': 'unknown tool: $toolName',
          'reason': 'Tool not registered in dispatcher',
        });
    }
  }
}
