import 'package:flutter/material.dart';

/// Maps an account type string to its corresponding [IconData].
///
/// Supported types:
/// - 'bank' → [Icons.account_balance_rounded]
/// - 'cash' → [Icons.payments_rounded]
/// - 'credit_card' → [Icons.credit_card_rounded]
/// - 'investment' → [Icons.trending_up_rounded]
/// - 'crypto' → [Icons.currency_bitcoin_rounded]
/// - others → [Icons.account_balance_wallet_outlined]
IconData accountIconForType(String type) {
  switch (type) {
    case 'bank':
      return Icons.account_balance_rounded;
    case 'cash':
      return Icons.payments_rounded;
    case 'credit_card':
      return Icons.credit_card_rounded;
    case 'investment':
      return Icons.trending_up_rounded;
    case 'crypto':
      return Icons.currency_bitcoin_rounded;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}
