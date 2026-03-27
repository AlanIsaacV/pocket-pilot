const kAllowedCurrenciesPrefKey = 'transaction.allowed_currencies';
const kDefaultCurrencyPrefKey = 'transaction.default_currency';

const kInitialAllowedCurrencies = <String>[
  'MXN',
  'USD',
  'EUR',
  'GBP',
  'CAD',
  'COP',
  'ARS',
  'BRL',
  'CLP',
  'PEN',
];

const kInitialDefaultCurrency = 'MXN';

const kSuggestedCurrencies = <({String code, String name})>[
  (code: 'MXN', name: 'Peso Mexicano'),
  (code: 'USD', name: 'US Dollar'),
  (code: 'EUR', name: 'Euro'),
  (code: 'GBP', name: 'British Pound'),
  (code: 'CAD', name: 'Canadian Dollar'),
  (code: 'COP', name: 'Peso Colombiano'),
  (code: 'ARS', name: 'Peso Argentino'),
  (code: 'BRL', name: 'Real Brasileno'),
  (code: 'CLP', name: 'Peso Chileno'),
  (code: 'PEN', name: 'Sol Peruano'),
];

const kCurrencyCodeRegex = r'^[A-Z0-9]{2,10}$';

final RegExp _currencyCodePattern = RegExp(kCurrencyCodeRegex);
final Map<String, String> _suggestedNameByCode = {
  for (final c in kSuggestedCurrencies) c.code: c.name,
};

String normalizeCurrencyCode(String code) => code.trim().toUpperCase();

bool isValidCurrencyCode(String code) {
  return _currencyCodePattern.hasMatch(normalizeCurrencyCode(code));
}

String currencyNameForCode(String code) {
  return _suggestedNameByCode[normalizeCurrencyCode(code)] ??
      'Moneda personalizada';
}

bool isSuggestedCurrencyCode(String code) {
  return _suggestedNameByCode.containsKey(normalizeCurrencyCode(code));
}
