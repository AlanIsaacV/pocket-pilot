import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

class GoalTool {
  final DatabaseHelper _db;
  final DashboardRepository _dashboardRepo;

  GoalTool({
    required DatabaseHelper db,
    required DashboardRepository dashboardRepo,
  }) : _db = db,
       _dashboardRepo = dashboardRepo;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    try {
      final goalId = args['goal_id'] as String?;
      final goalName = args['goal_name'] as String?;

      final db = await _db.database;
      List<Map<String, dynamic>> rows;

      if (goalId != null) {
        rows = await db.query(
          'goals',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [goalId],
          limit: 1,
        );
      } else if (goalName != null) {
        rows = await db.query(
          'goals',
          where: 'name LIKE ? COLLATE NOCASE AND deleted_at IS NULL',
          whereArgs: ['%$goalName%'],
          limit: 1,
        );
      } else {
        return const AIToolResult(
          success: false,
          content: '{"error": "Se requiere goal_id o goal_name"}',
        );
      }

      if (rows.isEmpty) {
        return const AIToolResult(
          success: false,
          content: '{"error": "Meta no encontrada"}',
        );
      }

      final goal = GoalModel.fromMap(rows.first);

      final metrics = await _dashboardRepo.calculateAllMetrics();
      final currencyMetrics = metrics[goal.currencyCode];
      final liquidCents = currencyMetrics?.liquidAssetsCents ?? 0;

      return AIToolResult(
        success: true,
        content: jsonEncode({
          'name': goal.name,
          'target_amount_cents': goal.targetAmountCents,
          'currency_code': goal.currencyCode,
          'target_date': goal.targetDate,
          'liquid_assets_cents': liquidCents,
          'remaining_cents': goal.targetAmountCents - liquidCents,
        }),
      );
    } catch (e) {
      dev.log('GoalTool error: $e');
      return AIToolResult(
        success: false,
        content: jsonEncode({'error': 'Error al consultar meta: $e'}),
      );
    }
  }
}
