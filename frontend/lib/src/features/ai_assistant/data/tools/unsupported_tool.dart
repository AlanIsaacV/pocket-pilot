import 'dart:convert';
import 'dart:developer' as dev;

import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_result.dart';

class UnsupportedTool {
  final AIRemoteService _remote;

  UnsupportedTool({required AIRemoteService remote}) : _remote = remote;

  Future<AIToolResult> execute(Map<String, dynamic> args) async {
    final intent = args['user_intent'] as String? ?? 'unknown';
    final reason = args['reason'] as String? ?? 'unknown';

    dev.log('UnsupportedTool: intent="$intent", reason="$reason"');

    _remote
        .reportUnsupportedTool(userIntent: intent, reason: reason)
        .catchError((_) {});

    return AIToolResult(
      success: false,
      content: jsonEncode({
        'error': 'Funcion no soportada',
        'user_intent': intent,
        'reason': reason,
      }),
    );
  }
}
