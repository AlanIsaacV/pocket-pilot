// ============================================================
// Tokens de color — Design System "Premium Fintech Dark & Elegant"
// ============================================================
//
// Paleta principal en modo oscuro. La paleta clara adapta los mismos
// roles usando superficies claras y texto oscuro.
//
// Uso: AppColors.primary, AppColors.surface, etc.
// No usar los hex directamente fuera de este archivo.

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ----------------------------------------------------------
  // Paleta oscura (dark-first)
  // ----------------------------------------------------------

  /// Fondo principal de la app. El negro más profundo.
  static const Color backgroundDark = Color(0xFF09090B);

  /// Superficie de tarjetas, drawers, bottom sheets.
  static const Color surfaceDark = Color(0xFF18181B);

  /// Superficie elevada: inputs, chips, items seleccionados.
  static const Color surfaceElevatedDark = Color(0xFF27272A);

  /// Texto primario sobre superficies oscuras.
  static const Color textPrimaryDark = Color(0xFFFAFAFA);

  /// Texto secundario / placeholders sobre superficies oscuras.
  static const Color textMutedDark = Color(0xFFA1A1AA);

  // ----------------------------------------------------------
  // Paleta clara
  // ----------------------------------------------------------

  /// Fondo principal en modo claro.
  static const Color backgroundLight = Color(0xFFF4F4F5);

  /// Superficie de tarjetas en modo claro.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Superficie elevada en modo claro.
  static const Color surfaceElevatedLight = Color(0xFFE4E4E7);

  /// Texto primario en modo claro.
  static const Color textPrimaryLight = Color(0xFF09090B);

  /// Texto secundario en modo claro.
  static const Color textMutedLight = Color(0xFF71717A);

  // ----------------------------------------------------------
  // Colores semánticos (iguales en ambos modos)
  // ----------------------------------------------------------

  /// Acción principal / ingresos / positivo.
  static const Color primary = Color(0xFF00FF66);

  /// Foreground sobre primary (negro para contraste con el verde neón).
  static const Color onPrimary = Color(0xFF09090B);

  /// Acento secundario / gastos activos.
  static const Color accent = Color(0xFF00E5FF);

  /// Error / pérdidas / gastos / destructivo.
  static const Color error = Color(0xFFFF3366);

  /// Foreground sobre error.
  static const Color onError = Color(0xFFFAFAFA);

  // ----------------------------------------------------------
  // Colores de categorías (usados en pickers y chips)
  // ----------------------------------------------------------

  static const Color categoryGold = Color(0xFFFFD700);
  static const Color categoryPurple = Color(0xFFB026FF);
  static const Color categoryOrange = Color(0xFFFF8C00);
  static const Color categoryYellow = Color(0xFFFFD600);
  static const Color categoryCyan = Color(0xFF00E5FF);
  static const Color categoryGreen = Color(0xFF00FF66);
  static const Color categoryRed = Color(0xFFFF3366);
  static const Color categoryPink = Color(0xFFFF69B4);
  static const Color categoryBlue = Color(0xFF4D9FFF);
  static const Color categoryTeal = Color(0xFF00CCC8);
  static const Color categoryLime = Color(0xFFB8FF00);
  static const Color categoryAmber = Color(0xFFFFC107);

  /// Lista ordenada de los 12 colores para el color picker.
  static const List<Color> categoryPresets = [
    categoryGreen,
    categoryCyan,
    categoryBlue,
    categoryPurple,
    categoryPink,
    categoryRed,
    categoryOrange,
    categoryAmber,
    categoryYellow,
    categoryLime,
    categoryTeal,
    categoryGold,
  ];
}
