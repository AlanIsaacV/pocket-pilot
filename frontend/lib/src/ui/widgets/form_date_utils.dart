import 'package:flutter/material.dart';

/// Formats a [DateTime] for display as DD/MM/YYYY.
String formatDateDisplay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Formats a [DateTime] as ISO 8601 (YYYY-MM-DD) for storage.
String formatDateISO(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Shows a date picker dialog themed with the current context's color scheme.
///
/// Returns the selected date or null if the user cancels.
Future<DateTime?> pickDate(
  BuildContext context,
  DateTime initial, {
  DateTime? firstDate,
  DateTime? lastDate,
}) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: Theme.of(context).colorScheme.primary,
              ),
        ),
        child: child!,
      ),
    );
