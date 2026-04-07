import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:grpc/grpc.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:pocket_pilot/src/features/ai_assistant/data/ai_context_builder.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_tool_dispatcher.dart';
import 'package:pocket_pilot/src/features/ai_assistant/domain/ai_tool_definitions.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart';

enum AISessionState { idle, ready, listening, processing, speaking, error }

class AISessionController extends ChangeNotifier {
  final AIRemoteService _remote;
  final AIToolDispatcher _dispatcher;
  final AIContextBuilder _contextBuilder;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final List<AIMessage> _sessionMessages = [];
  final List<AIToolDefinition> _toolDefinitions = aiToolDefinitions;

  AISessionState _state = AISessionState.idle;
  AISessionState get state => _state;

  String _displayText = '';
  String get displayText => _displayText;

  int _toolCallCount = 0;
  static const _maxToolCalls = 10;

  AISessionController({
    required AIRemoteService remote,
    required AIToolDispatcher dispatcher,
    required AIContextBuilder contextBuilder,
  }) : _remote = remote,
       _dispatcher = dispatcher,
       _contextBuilder = contextBuilder {
    _tts.setCompletionHandler(_onSpeakingDone);
  }

  Future<void> openSession() async {
    if (_state != AISessionState.idle) return;

    _sessionMessages.clear();
    _toolCallCount = 0;

    try {
      final systemPrompt = await _contextBuilder.buildSystemPrompt();
      _sessionMessages.add(
        AIMessage(role: AIRole.AI_ROLE_SYSTEM, content: systemPrompt),
      );

      final available = await _speech.initialize();
      if (!available) {
        _onError('El reconocimiento de voz no esta disponible', fatal: true);
        return;
      }

      _state = AISessionState.ready;
      _displayText = '';
      notifyListeners();
    } catch (e) {
      _onError('Error al iniciar sesion: $e');
    }
  }

  void endSession() {
    _speech.stop();
    _tts.stop();
    _sessionMessages.clear();
    _toolCallCount = 0;
    _state = AISessionState.idle;
    _displayText = '';
    notifyListeners();
  }

  void startListening() {
    if (_state != AISessionState.ready && _state != AISessionState.error) {
      return;
    }

    _state = AISessionState.listening;
    _displayText = '';
    notifyListeners();

    _speech.listen(
      onResult: (result) {
        _displayText = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          _onSpeechResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'es_MX',
    );

    Future<void>.delayed(const Duration(seconds: 32), () {
      if (_state == AISessionState.listening) {
        stopListening();
      }
    });
  }

  void stopListening() {
    if (_state != AISessionState.listening) return;
    _speech.stop();
  }

  void _onSpeechResult(String text) {
    if (text.trim().isEmpty) {
      _state = AISessionState.ready;
      _displayText = '';
      notifyListeners();
      return;
    }

    _sessionMessages.add(AIMessage(role: AIRole.AI_ROLE_USER, content: text));

    _state = AISessionState.processing;
    _displayText = 'Procesando...';
    notifyListeners();

    _sendToBackend();
  }

  Future<void> _sendToBackend() async {
    try {
      final response = await _remote.chat(
        messages: _sessionMessages,
        tools: _toolDefinitions,
      );

      if (response.hasToolCall()) {
        await _handleToolCall(response.toolCall);
      } else {
        _handleTextResponse(response.text);
      }
    } on GrpcError catch (e) {
      if (e.code == StatusCode.resourceExhausted) {
        _onError(e.message ?? 'Limite de uso alcanzado');
      } else if (e.code == StatusCode.unavailable) {
        _onError('No hay conexion a internet');
      } else {
        _onError('Error de conexion: ${e.message}');
      }
    } catch (_) {
      _onError('Ocurrio un error, intenta de nuevo mas tarde');
    }
  }

  Future<void> _handleToolCall(AIToolCall toolCall) async {
    _sessionMessages.add(
      AIMessage(role: AIRole.AI_ROLE_ASSISTANT, toolCall: toolCall),
    );

    try {
      final args = jsonDecode(toolCall.arguments) as Map<String, dynamic>;
      final result = await _dispatcher.dispatch(toolCall.name, args);

      _sessionMessages.add(
        AIMessage(
          role: AIRole.AI_ROLE_TOOL,
          toolCallId: toolCall.id,
          content: result.content,
        ),
      );

      _toolCallCount++;

      if (_toolCallCount >= _maxToolCalls) {
        _sessionMessages.add(
          AIMessage(
            role: AIRole.AI_ROLE_USER,
            content: 'Por favor resume y responde con texto.',
          ),
        );
      }

      await _sendToBackend();
    } catch (e) {
      _sessionMessages.add(
        AIMessage(
          role: AIRole.AI_ROLE_TOOL,
          toolCallId: toolCall.id,
          content: jsonEncode({'error': 'Error ejecutando herramienta: $e'}),
        ),
      );
      await _sendToBackend();
    }
  }

  Future<void> _handleTextResponse(String text) async {
    _sessionMessages.add(
      AIMessage(role: AIRole.AI_ROLE_ASSISTANT, content: text),
    );

    _state = AISessionState.speaking;
    _displayText = text;
    notifyListeners();

    await _tts.setLanguage('es-MX');
    await _tts.speak(text);
  }

  void _onSpeakingDone() {
    if (_state != AISessionState.speaking) return;

    _state = AISessionState.ready;
    notifyListeners();
  }

  Future<void> _onError(String message, {bool fatal = false}) async {
    _state = AISessionState.error;
    _displayText = message;
    notifyListeners();

    await _tts.setLanguage('es-MX');
    _tts.setCompletionHandler(() {
      if (fatal) {
        endSession();
      } else {
        _state = AISessionState.ready;
        notifyListeners();
      }
      _tts.setCompletionHandler(_onSpeakingDone);
    });
    await _tts.speak(message);
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
