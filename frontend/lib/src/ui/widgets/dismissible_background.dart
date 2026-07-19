import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';

/// The color treatment used by a [DismissibleBackground].
enum DismissibleBackgroundColorScheme { delete, archive, edit }

/// Standard background revealed while swiping a [Dismissible] item.
class DismissibleBackground extends StatelessWidget {
  final String label;
  final IconData icon;
  final DismissibleBackgroundColorScheme colorScheme;
  final DismissDirection direction;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry margin;

  const DismissibleBackground({
    super.key,
    required this.label,
    required this.icon,
    this.colorScheme = DismissibleBackgroundColorScheme.delete,
    this.direction = DismissDirection.endToStart,
    this.alignment,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionColor = switch (colorScheme) {
      DismissibleBackgroundColorScheme.delete => scheme.error,
      DismissibleBackgroundColorScheme.archive => scheme.tertiary,
      DismissibleBackgroundColorScheme.edit => scheme.primary,
    };

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: actionColor.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: actionColor.withValues(alpha: 0.5)),
      ),
      alignment: alignment ?? _alignmentForDirection(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: actionColor,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, color: actionColor),
        ],
      ),
    );
  }

  AlignmentGeometry _alignmentForDirection() {
    return switch (direction) {
      DismissDirection.startToEnd => Alignment.centerLeft,
      _ => Alignment.centerRight,
    };
  }
}
