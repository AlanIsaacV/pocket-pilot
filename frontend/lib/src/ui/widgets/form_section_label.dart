import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A muted, semibold label for grouping form fields.
class FormSectionLabel extends StatelessWidget {
  final String text;
  final double fontSize;

  const FormSectionLabel(this.text, {super.key, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }
}
