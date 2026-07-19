import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';

/// Shows the standard currency picker and returns the selected currency code.
///
/// The picker owns the preferences round-trip so callers only need to apply a
/// non-null result. [mustIncludeCode] keeps a related currency, such as an
/// account's currency, available even when it is not currently allowed.
Future<String?> showCurrencyPicker(
  BuildContext context, {
  required String selectedCode,
  String? mustIncludeCode,
}) async {
  // Bottom-sheet routes do not inherit providers, so capture this dependency
  // from the caller before opening the sheet.
  final preferencesStore = context.read<CurrencyPreferencesLocalStore>();
  final snapshot = await preferencesStore.getSnapshot();
  if (!context.mounted) return null;

  final selection = await showFormBottomSheet<Object>(
    context: context,
    builder: (sheetContext) => ScrollableBottomSheet(
      title: 'Moneda',
      children: [
        SheetItem(
          icon: Icons.tune_rounded,
          label: 'Configurar monedas',
          onTap: () => Navigator.pop(
            sheetContext,
            _CurrencyPickerSelection.openPreferences,
          ),
        ),
        ..._currencyCodesFor(
          snapshot.allowedCodes,
          selectedCode: selectedCode,
          mustIncludeCode: mustIncludeCode,
        ).map(
          (code) => SheetItem(
            label: '$code — ${currencyNameForCode(code)}',
            onTap: () => Navigator.pop(sheetContext, code),
          ),
        ),
      ],
    ),
  );

  if (selection is String) return selection;
  if (selection != _CurrencyPickerSelection.openPreferences) return null;

  if (!context.mounted) return null;
  await context.push<bool>('/settings/currency');
  if (!context.mounted) return null;

  final refreshedSnapshot = await preferencesStore.getSnapshot();
  if (!context.mounted) return null;

  final allowedAfterPreferences = <String>{...refreshedSnapshot.allowedCodes};
  if (mustIncludeCode != null) allowedAfterPreferences.add(mustIncludeCode);
  if (allowedAfterPreferences.contains(selectedCode)) return selectedCode;

  return mustIncludeCode ?? refreshedSnapshot.defaultCode;
}

List<String> _currencyCodesFor(
  List<String> allowedCodes, {
  required String selectedCode,
  String? mustIncludeCode,
}) {
  final codes = <String>{...allowedCodes, selectedCode};
  if (mustIncludeCode != null) codes.add(mustIncludeCode);
  return codes.toList()..sort(compareCurrencyCodes);
}

enum _CurrencyPickerSelection { openPreferences }
