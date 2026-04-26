// ============================================================
// ParserEngine — interpreta NotificationParserDefinition contra una notificación
// ============================================================
//
// Reglas:
//   1. Evalúa `ignore_patterns` primero. Si alguno matchea, descarta la notificación.
//   2. Recorre `patterns` en orden, primer match gana.
//   3. Aplica las transformaciones a los grupos capturados (whitelist cerrada).
//   4. Devuelve un `ParserMatch` con los campos extraídos, o null.
//
// Mitigación ReDoS: cada `RegExp.firstMatch` se ejecuta dentro de un timeout
// de 50 ms. Si excede, descarta el patrón y continúa. El límite a la longitud
// del regex se valida en backend cuando viene de candidate_parsers (Fase 4).

import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';

class ParserMatch {
  final NotificationParserDefinition parser;
  final NotificationPattern pattern;
  final int amountCents;
  final String currencyCode;
  final String? merchantDescription;
  final String? cardLastDigits;
  final String transactionType;

  const ParserMatch({
    required this.parser,
    required this.pattern,
    required this.amountCents,
    required this.currencyCode,
    required this.transactionType,
    this.merchantDescription,
    this.cardLastDigits,
  });
}

/// Conjunto cerrado de transformaciones que pueden aplicarse a un grupo
/// capturado. NUNCA se interpretan strings desde el JSON; sólo identificadores.
typedef _Transform = String Function(String input);
final Map<String, _Transform> _kTransforms = {
  'upper': (s) => s.toUpperCase(),
  'lower': (s) => s.toLowerCase(),
  'trim': (s) => s.trim(),
};

class ParserEngine {
  /// Tiempo máximo permitido para que un solo `firstMatch` retorne. En Dart,
  /// `RegExp` no soporta cancelación cooperativa; este límite es un safety net
  /// en caso de patrones patológicos provenientes del backend (Fase 4).
  static const _matchTimeoutMs = 50;

  ParserMatch? tryMatch(
    CapturedNotificationModel notification,
    NotificationParserDefinition parser,
  ) {
    if (!parser.packageNames.contains(notification.packageName)) {
      return null;
    }

    final fields = _fieldsOf(notification);

    for (final ignore in parser.ignorePatterns) {
      final regex = _compile(ignore.regex, ignore.flags);
      if (regex == null) continue;
      final field = fields[ignore.field] ?? '';
      if (_safeFirstMatch(regex, field) != null) {
        return null; // matched ignore → discard silently
      }
    }

    for (final pattern in parser.patterns) {
      final regex = _compile(pattern.match.regex, pattern.match.flags);
      if (regex == null) continue;
      final field = fields[pattern.match.field] ?? '';
      final match = _safeFirstMatch(regex, field);
      if (match == null) continue;

      final extracted = _extractFields(pattern, match, parser);
      if (extracted == null) continue;
      return extracted;
    }

    return null;
  }

  Map<String, String> _fieldsOf(CapturedNotificationModel n) => {
        'title': n.title ?? '',
        'text': n.text ?? '',
        'big_text': n.bigText ?? '',
      };

  RegExp? _compile(String source, String? flags) {
    try {
      final caseSensitive = !(flags?.contains('i') ?? false);
      final multiLine = flags?.contains('m') ?? false;
      final dotAll = flags?.contains('s') ?? false;
      return RegExp(
        source,
        caseSensitive: caseSensitive,
        multiLine: multiLine,
        dotAll: dotAll,
        unicode: true,
      );
    } catch (_) {
      // Regex inválido viniendo de backend: ignorar silenciosamente.
      return null;
    }
  }

  RegExpMatch? _safeFirstMatch(RegExp regex, String input) {
    final stopwatch = Stopwatch()..start();
    try {
      final m = regex.firstMatch(input);
      if (stopwatch.elapsedMilliseconds > _matchTimeoutMs) {
        return null;
      }
      return m;
    } finally {
      stopwatch.stop();
    }
  }

  ParserMatch? _extractFields(
    NotificationPattern pattern,
    RegExpMatch match,
    NotificationParserDefinition parser,
  ) {
    String? captureValue(String groupName) {
      try {
        return match.namedGroup(groupName);
      } catch (_) {
        // Grupo no existe en el regex: el JSON está mal escrito.
        return null;
      }
    }

    String? extract(String fieldKey) {
      final mapping = pattern.captures[fieldKey];
      if (mapping == null) return null;
      var value = captureValue(mapping.from)?.trim() ?? '';
      if (mapping.transform != null) {
        final transform = _kTransforms[mapping.transform];
        if (transform != null) value = transform(value);
      }
      if (value.isEmpty) {
        return mapping.defaultValue;
      }
      return value;
    }

    final amountRaw = extract('amount_cents');
    if (amountRaw == null) return null;
    final amountCents = _moneyToCents(amountRaw);
    if (amountCents == null || amountCents <= 0) return null;

    final currency = extract('currency_code')?.toUpperCase() ?? parser.defaultCurrency;
    final merchant = extract('merchant_description');
    final cardDigits = extract('card_last_digits');

    final type = pattern.transactionType;
    if (type != 'income' && type != 'expense') return null;

    return ParserMatch(
      parser: parser,
      pattern: pattern,
      amountCents: amountCents,
      currencyCode: currency,
      merchantDescription: merchant,
      cardLastDigits: cardDigits,
      transactionType: type,
    );
  }

  /// Acepta strings tipo "1,234.56" o "1234.56" y los convierte a centavos.
  /// La transformación `money_to_cents` se invoca aquí (no como entry en
  /// `_kTransforms`) porque su salida es un int, no String.
  int? _moneyToCents(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '')
        .replaceAll(r'$', '');
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }
}
