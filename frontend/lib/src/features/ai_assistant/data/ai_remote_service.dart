import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pbgrpc.dart';

class AIRemoteService {
  late final AIAssistantServiceClient _client;

  AIRemoteService() {
    _client = AIAssistantServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<AIChatResponse> chat({
    required List<AIMessage> messages,
    required List<AIToolDefinition> tools,
  }) async {
    final request = AIChatRequest(messages: messages, tools: tools);
    return _client.chat(request);
  }

  Future<void> reportUnsupportedTool({
    required String userIntent,
    required String reason,
  }) async {
    final request = ReportUnsupportedToolRequest(
      userIntent: userIntent,
      reason: reason,
    );
    await _client.reportUnsupportedTool(request);
  }
}
