enum CalcOperator { add, subtract, multiply, divide }

extension CalcOperatorSymbol on CalcOperator {
  String get symbol => switch (this) {
    CalcOperator.add => '+',
    CalcOperator.subtract => '-',
    CalcOperator.multiply => '*',
    CalcOperator.divide => '/',
  };
}

class TransactionAmountCalculator {
  TransactionAmountCalculator({String initialAmount = '0'}) {
    reset(initialAmount);
  }

  String _displayAmount = '0';
  String _expressionDisplay = '';
  String _lastValidAmount = '0';
  String? _lastErrorMessage;

  String _leftOperand = '0';
  String _activeOperand = '0';
  CalcOperator? _pendingOperator;
  bool _hasRightOperandInput = false;
  bool _justResolved = false;
  final List<String> _tokens = <String>[];

  String get displayAmount => _displayAmount;
  String get expressionDisplay => _expressionDisplay;
  String get lastValidAmount => _lastValidAmount;
  bool get hasPendingExpression => _pendingOperator != null;

  void reset(String amount) {
    final normalized = _normalizeTypedNumber(amount);
    _displayAmount = normalized;
    _expressionDisplay = '';
    _lastValidAmount = _normalizedWithoutTrailingDot(normalized);
    _leftOperand = _lastValidAmount;
    _activeOperand = normalized;
    _pendingOperator = null;
    _hasRightOperandInput = false;
    _justResolved = false;
    _lastErrorMessage = null;
    _tokens.clear();
  }

  void onDigit(String digit) {
    if (digit.length != 1 || !_isDigit(digit.codeUnitAt(0))) return;

    if (_justResolved && _pendingOperator == null) {
      reset(digit);
      return;
    }

    if (_pendingOperator != null) {
      _activeOperand = _appendDigit(_activeOperand, digit);
      _displayAmount = _activeOperand;
      _hasRightOperandInput = true;
      _refreshExpressionDisplay();
      return;
    }

    _activeOperand = _appendDigit(_activeOperand, digit);
    _displayAmount = _activeOperand;
    _lastValidAmount = _normalizedWithoutTrailingDot(_displayAmount);
    _justResolved = false;
    _expressionDisplay = '';
  }

  void onDecimalPoint() {
    if (_justResolved && _pendingOperator == null) {
      reset('0.');
      return;
    }

    if (_pendingOperator != null) {
      _activeOperand = _appendDecimalPoint(_activeOperand);
      _displayAmount = _activeOperand;
      _hasRightOperandInput = true;
      _refreshExpressionDisplay();
      return;
    }

    _activeOperand = _appendDecimalPoint(_activeOperand);
    _displayAmount = _activeOperand;
    _lastValidAmount = _normalizedWithoutTrailingDot(_displayAmount);
    _justResolved = false;
    _expressionDisplay = '';
  }

  void onBackspace() {
    if (_justResolved && _pendingOperator == null) {
      _justResolved = false;
      _activeOperand = _displayAmount;
    }

    if (_pendingOperator != null) {
      _activeOperand = _backspaceOperand(_activeOperand);
      _displayAmount = _activeOperand;
      _hasRightOperandInput =
          _activeOperand != '0' || _activeOperand.contains('.');
      _refreshExpressionDisplay();
      return;
    }

    _activeOperand = _backspaceOperand(_activeOperand);
    _displayAmount = _activeOperand;
    _lastValidAmount = _normalizedWithoutTrailingDot(_displayAmount);
    _expressionDisplay = '';
  }

  void onOperator(CalcOperator op) {
    if (_pendingOperator == null) {
      _leftOperand = _normalizedWithoutTrailingDot(_displayAmount);
      _tokens
        ..clear()
        ..add(_leftOperand)
        ..add(op.symbol);
      _pendingOperator = op;
      _activeOperand = '0';
      _hasRightOperandInput = false;
      _justResolved = false;
      _refreshExpressionDisplay();
      return;
    }

    if (!_hasRightOperandInput) {
      _pendingOperator = op;
      if (_tokens.isNotEmpty) {
        _tokens[_tokens.length - 1] = op.symbol;
      }
      _refreshExpressionDisplay();
      return;
    }

    final rightOperand = _normalizedWithoutTrailingDot(_activeOperand);
    final evaluated = _evaluate(_leftOperand, _pendingOperator!, rightOperand);
    if (evaluated == null) {
      _fallbackToLastValidAmount();
      return;
    }

    _tokens.add(rightOperand);
    _leftOperand = evaluated;
    _displayAmount = evaluated;
    _lastValidAmount = evaluated;
    _activeOperand = '0';
    _pendingOperator = op;
    _hasRightOperandInput = false;
    _justResolved = false;
    _tokens.add(op.symbol);
    _refreshExpressionDisplay();
  }

  bool onEquals() {
    if (_pendingOperator == null) {
      return true;
    }

    final committed = _commitPending(includeEqualsInHistory: true);
    if (!committed) {
      _fallbackToLastValidAmount();
    }
    return committed;
  }

  bool commitPendingIfAny({bool includeEqualsInHistory = true}) {
    if (_pendingOperator == null) {
      return true;
    }

    final committed = _commitPending(
      includeEqualsInHistory: includeEqualsInHistory,
    );
    if (!committed) {
      _fallbackToLastValidAmount();
    }
    return committed;
  }

  String? consumeLastError() {
    final message = _lastErrorMessage;
    _lastErrorMessage = null;
    return message;
  }

  int getAmountMinorForSaveRounded2() {
    return _toMinorUnitsHalfAwayFromZero(_displayAmount);
  }

  String getAmountForSaveRounded2() {
    final minor = getAmountMinorForSaveRounded2();
    final sign = minor < 0 ? '-' : '';
    final absMinor = minor.abs();
    final integerPart = absMinor ~/ 100;
    final decimalPart = (absMinor % 100).toString().padLeft(2, '0');

    if (decimalPart == '00') {
      return '$sign$integerPart';
    }
    return '$sign$integerPart.$decimalPart';
  }

  bool _commitPending({required bool includeEqualsInHistory}) {
    if (_pendingOperator == null) {
      return true;
    }

    if (!_hasRightOperandInput) {
      _setError('Operacion incompleta. Se uso el ultimo monto valido.');
      return false;
    }

    final rightOperand = _normalizedWithoutTrailingDot(_activeOperand);
    _tokens.add(rightOperand);

    final evaluated = _evaluate(_leftOperand, _pendingOperator!, rightOperand);
    if (evaluated == null) {
      return false;
    }

    final history = _tokens.join(' ');
    _displayAmount = evaluated;
    _activeOperand = evaluated;
    _leftOperand = evaluated;
    _lastValidAmount = evaluated;
    _pendingOperator = null;
    _hasRightOperandInput = false;
    _justResolved = true;
    _tokens
      ..clear()
      ..add(evaluated);
    _expressionDisplay = includeEqualsInHistory
        ? '$history = $evaluated'
        : history;
    return true;
  }

  String? _evaluate(String leftRaw, CalcOperator op, String rightRaw) {
    final left = _parseNumber(leftRaw);
    final right = _parseNumber(rightRaw);
    if (left == null || right == null) {
      _setError('Operacion invalida. Se uso el ultimo monto valido.');
      return null;
    }

    if (op == CalcOperator.divide && right == 0) {
      _setError(
        'No se puede dividir entre cero. Se uso el ultimo monto valido.',
      );
      return null;
    }

    final result = switch (op) {
      CalcOperator.add => left + right,
      CalcOperator.subtract => left - right,
      CalcOperator.multiply => left * right,
      CalcOperator.divide => left / right,
    };

    if (!result.isFinite) {
      _setError('Operacion invalida. Se uso el ultimo monto valido.');
      return null;
    }

    return _formatResult(result);
  }

  void _fallbackToLastValidAmount() {
    final fallback = _normalizedWithoutTrailingDot(_lastValidAmount);
    _displayAmount = fallback;
    _activeOperand = fallback;
    _leftOperand = fallback;
    _pendingOperator = null;
    _hasRightOperandInput = false;
    _justResolved = false;
    _tokens.clear();
    _expressionDisplay = '';
  }

  void _refreshExpressionDisplay() {
    if (_pendingOperator == null) {
      return;
    }

    final expressionTokens = List<String>.from(_tokens);
    if (_hasRightOperandInput || _activeOperand.contains('.')) {
      expressionTokens.add(_activeOperand);
    }
    _expressionDisplay = expressionTokens.join(' ');
  }

  void _setError(String message) {
    _lastErrorMessage = message;
  }

  static String _appendDigit(String current, String digit) {
    final normalized = _normalizeTypedNumber(current);

    if (normalized == '0') {
      return digit;
    }
    if (normalized == '-0') {
      return '-$digit';
    }
    return '$normalized$digit';
  }

  static String _appendDecimalPoint(String current) {
    final normalized = _normalizeTypedNumber(current);
    if (normalized.contains('.')) {
      return normalized;
    }
    return '$normalized.';
  }

  static String _backspaceOperand(String current) {
    final normalized = _normalizeTypedNumber(current);
    if (normalized.length <= 1 || normalized == '-0') {
      return '0';
    }

    final next = normalized.substring(0, normalized.length - 1);
    if (next == '-' || next.isEmpty) {
      return '0';
    }
    return _normalizeTypedNumber(next);
  }

  static String _formatResult(double value) {
    if (value == 0) {
      return '0';
    }
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }

    final fixed = value.toStringAsFixed(12);
    return _trimTrailingZeros(fixed);
  }

  static double? _parseNumber(String raw) {
    final normalized = _normalizedWithoutTrailingDot(raw);
    return double.tryParse(normalized);
  }

  static String _trimTrailingZeros(String input) {
    var value = input;
    while (value.contains('.') && value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    if (value == '-0') {
      return '0';
    }
    return value;
  }

  static String _normalizedWithoutTrailingDot(String input) {
    var normalized = _normalizeTypedNumber(input);
    if (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty || normalized == '-') {
      return '0';
    }
    if (normalized == '-0') {
      return '0';
    }
    return normalized;
  }

  static String _normalizeTypedNumber(String input) {
    var value = input.trim();
    if (value.isEmpty || value == '-') {
      return '0';
    }

    if (value.startsWith('-.')) {
      value = '-0${value.substring(1)}';
    } else if (value.startsWith('.')) {
      value = '0$value';
    }

    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final dotIndex = unsigned.indexOf('.');

    String integerPart;
    String decimalPart;
    var keepDot = false;

    if (dotIndex >= 0) {
      integerPart = unsigned.substring(0, dotIndex);
      decimalPart = unsigned.substring(dotIndex + 1);
      keepDot = unsigned.endsWith('.');
    } else {
      integerPart = unsigned;
      decimalPart = '';
    }

    integerPart = _stripLeadingZeros(integerPart);
    if (integerPart.isEmpty) {
      integerPart = '0';
    }

    var rebuilt = integerPart;
    if (dotIndex >= 0) {
      rebuilt = '$integerPart.$decimalPart';
      if (keepDot && decimalPart.isEmpty) {
        rebuilt = '$integerPart.';
      }
    }

    if (negative && rebuilt != '0' && rebuilt != '0.') {
      rebuilt = '-$rebuilt';
    }

    return rebuilt;
  }

  static String _stripLeadingZeros(String input) {
    var i = 0;
    while (i < input.length - 1 && input.codeUnitAt(i) == 48) {
      i += 1;
    }
    return input.substring(i);
  }

  static int _toMinorUnitsHalfAwayFromZero(String rawAmount) {
    var normalized = _normalizedWithoutTrailingDot(rawAmount);
    final isNegative = normalized.startsWith('-');
    if (isNegative) {
      normalized = normalized.substring(1);
    }

    final parts = normalized.split('.');
    final wholePart = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length > 1 ? parts[1] : '';

    final padded = '${fraction}000';
    final centsPart = padded.substring(0, 2);
    final thirdDecimal = int.parse(padded[2]);

    var minor = int.parse(wholePart) * 100 + int.parse(centsPart);
    if (thirdDecimal >= 5) {
      minor += 1;
    }

    return isNegative ? -minor : minor;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;
}
