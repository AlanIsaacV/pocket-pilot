// ============================================================
// NotificationParser — schema declarativo para parsear notificaciones
// ============================================================
//
// Un `NotificationParser` describe cómo extraer campos estructurados
// (monto, moneda, comercio, dígitos de tarjeta) a partir de notificaciones
// push de un banco específico.
//
// El motor (`parser_engine.dart`) interpreta el schema sin código adicional;
// para agregar un banco nuevo basta con crear un JSON con la misma forma y
// dejarlo caer en backend (Fase 3+) o en assets/parsers/ (asset embebido).

import 'dart:convert';

class NotificationParserDefinition {
  final int schemaVersion;
  final String bankId;
  final String displayName;
  final List<String> packageNames;
  final int version;
  final String defaultCurrency;
  final List<NotificationIgnoreRule> ignorePatterns;
  final List<NotificationPattern> patterns;

  const NotificationParserDefinition({
    required this.schemaVersion,
    required this.bankId,
    required this.displayName,
    required this.packageNames,
    required this.version,
    required this.defaultCurrency,
    required this.ignorePatterns,
    required this.patterns,
  });

  factory NotificationParserDefinition.fromJson(Map<String, dynamic> json) {
    final ignore = (json['ignore_patterns'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NotificationIgnoreRule.fromJson)
        .toList(growable: false);
    final patterns = (json['patterns'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NotificationPattern.fromJson)
        .toList(growable: false);
    final pkgs = (json['package_names'] as List? ?? const [])
        .cast<String>()
        .toList(growable: false);

    return NotificationParserDefinition(
      schemaVersion: json['schema_version'] as int? ?? 1,
      bankId: json['bank_id'] as String,
      displayName: json['display_name'] as String? ?? json['bank_id'] as String,
      packageNames: pkgs,
      version: json['version'] as int? ?? 1,
      defaultCurrency: json['default_currency'] as String? ?? 'MXN',
      ignorePatterns: ignore,
      patterns: patterns,
    );
  }

  String toJsonString() => jsonEncode(_toJson());

  Map<String, dynamic> _toJson() => {
        'schema_version': schemaVersion,
        'bank_id': bankId,
        'display_name': displayName,
        'package_names': packageNames,
        'version': version,
        'default_currency': defaultCurrency,
        'ignore_patterns': ignorePatterns.map((e) => e.toJson()).toList(),
        'patterns': patterns.map((e) => e.toJson()).toList(),
      };
}

class NotificationIgnoreRule {
  final String field; // 'title' | 'text' | 'big_text'
  final String regex;
  final String? flags;

  const NotificationIgnoreRule({
    required this.field,
    required this.regex,
    this.flags,
  });

  factory NotificationIgnoreRule.fromJson(Map<String, dynamic> json) {
    return NotificationIgnoreRule(
      field: json['field'] as String,
      regex: json['regex'] as String,
      flags: json['flags'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'field': field,
        'regex': regex,
        if (flags != null) 'flags': flags,
      };
}

class NotificationPattern {
  final String id;

  /// 'income' | 'expense'
  final String transactionType;
  final NotificationMatchRule match;
  final Map<String, NotificationCaptureMapping> captures;

  const NotificationPattern({
    required this.id,
    required this.transactionType,
    required this.match,
    required this.captures,
  });

  factory NotificationPattern.fromJson(Map<String, dynamic> json) {
    final raw = (json['captures'] as Map?)?.cast<String, dynamic>() ?? const {};
    final captures = <String, NotificationCaptureMapping>{
      for (final entry in raw.entries)
        entry.key: NotificationCaptureMapping.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        ),
    };

    return NotificationPattern(
      id: json['id'] as String,
      transactionType: json['transaction_type'] as String,
      match: NotificationMatchRule.fromJson(
        (json['match'] as Map).cast<String, dynamic>(),
      ),
      captures: captures,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'transaction_type': transactionType,
        'match': match.toJson(),
        'captures': {
          for (final e in captures.entries) e.key: e.value.toJson(),
        },
      };
}

class NotificationMatchRule {
  final String field;
  final String regex;
  final String? flags;

  const NotificationMatchRule({
    required this.field,
    required this.regex,
    this.flags,
  });

  factory NotificationMatchRule.fromJson(Map<String, dynamic> json) {
    return NotificationMatchRule(
      field: json['field'] as String,
      regex: json['regex'] as String,
      flags: json['flags'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'field': field,
        'regex': regex,
        if (flags != null) 'flags': flags,
      };
}

class NotificationCaptureMapping {
  /// Nombre del grupo de captura en el regex (Dart: `(?<name>...)`).
  final String from;

  /// Una de las transformaciones whitelist del engine.
  /// Ver `parser_engine.dart` → `_kTransforms`.
  final String? transform;

  /// Valor por defecto si el grupo de captura es null o vacío después
  /// de transformar.
  final String? defaultValue;

  const NotificationCaptureMapping({
    required this.from,
    this.transform,
    this.defaultValue,
  });

  factory NotificationCaptureMapping.fromJson(Map<String, dynamic> json) {
    return NotificationCaptureMapping(
      from: json['from'] as String,
      transform: json['transform'] as String?,
      defaultValue: json['default'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'from': from,
        if (transform != null) 'transform': transform,
        if (defaultValue != null) 'default': defaultValue,
      };
}
