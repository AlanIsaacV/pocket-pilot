import 'dart:convert';

import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';

class CurrencyPreferencesSnapshot {
  final List<String> allowedCodes;
  final String defaultCode;

  const CurrencyPreferencesSnapshot({
    required this.allowedCodes,
    required this.defaultCode,
  });
}

final Map<String, int> _suggestedCurrencyOrder = {
  for (var i = 0; i < kSuggestedCurrencies.length; i++)
    kSuggestedCurrencies[i].code: i,
};

int compareCurrencyCodes(String a, String b) {
  final aOrder = _suggestedCurrencyOrder[a];
  final bOrder = _suggestedCurrencyOrder[b];
  if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
  if (aOrder != null && bOrder == null) return -1;
  if (aOrder == null && bOrder != null) return 1;
  return a.compareTo(b);
}

List<String> normalizeCurrencyCodes(List<String> codes) {
  final normalized =
      codes
          .map(normalizeCurrencyCode)
          .where(isValidCurrencyCode)
          .toSet()
          .toList()
        ..sort(compareCurrencyCodes);
  return normalized;
}

List<String> parseAllowedCurrencyCodes(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return normalizeCurrencyCodes(decoded.whereType<String>().toList());
  } catch (_) {
    return const [];
  }
}

String resolveDefaultCurrencyCode({
  required List<String> allowedCodes,
  required String? defaultRaw,
}) {
  final normalizedDefault = normalizeCurrencyCode(defaultRaw ?? '');
  if (isValidCurrencyCode(normalizedDefault) &&
      allowedCodes.contains(normalizedDefault)) {
    return normalizedDefault;
  }
  return allowedCodes.first;
}

CurrencyPreferencesSnapshot buildCurrencyPreferencesSnapshot({
  required String? allowedRaw,
  required String? defaultRaw,
}) {
  final parsedAllowed = parseAllowedCurrencyCodes(allowedRaw);
  final allowed = parsedAllowed.isEmpty
      ? List<String>.from(kInitialAllowedCurrencies)
      : parsedAllowed;
  final defaultCode = resolveDefaultCurrencyCode(
    allowedCodes: allowed,
    defaultRaw: defaultRaw,
  );
  return CurrencyPreferencesSnapshot(
    allowedCodes: allowed,
    defaultCode: defaultCode,
  );
}
