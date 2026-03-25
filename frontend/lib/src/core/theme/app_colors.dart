// ============================================================
// Tokens de color — Design System "Premium Fintech Muted Blue"
// ============================================================
//
// Paleta principal en modo oscuro. Azul grisáceo profesional,
// fondos casi negros con tinte azulado, acento muted blue.
//
// Uso: AppColors.primary, AppColors.surfaceDark, etc.
// No usar los hex directamente fuera de este archivo.

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ----------------------------------------------------------
  // Paleta oscura (dark-first)
  // ----------------------------------------------------------

  /// Fondo principal de la app.
  static const Color backgroundDark = Color(0xFF0D0E12);

  /// Superficie de tarjetas, drawers, bottom sheets.
  static const Color surfaceDark = Color(0xFF121318);

  /// Superficie contenedor: listas, secciones agrupadas.
  static const Color surfaceContainerDark = Color(0xFF181920);

  /// Superficie elevada: inputs, chips, items seleccionados.
  static const Color surfaceElevatedDark = Color(0xFF1E1F26);

  /// Superficie brillante: hover, pressed states.
  static const Color surfaceBrightDark = Color(0xFF2A2C34);

  /// Texto primario sobre superficies oscuras.
  static const Color textPrimaryDark = Color(0xFFE4E4F0);

  /// Texto secundario / placeholders sobre superficies oscuras.
  static const Color textMutedDark = Color(0xFF73757F);

  // ----------------------------------------------------------
  // Paleta clara
  // ----------------------------------------------------------

  /// Fondo principal en modo claro.
  static const Color backgroundLight = Color(0xFFF0F1F5);

  /// Superficie de tarjetas en modo claro.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Superficie contenedor en modo claro.
  static const Color surfaceContainerLight = Color(0xFFF5F5FA);

  /// Superficie elevada en modo claro.
  static const Color surfaceElevatedLight = Color(0xFFE8E9F0);

  /// Texto primario en modo claro.
  static const Color textPrimaryLight = Color(0xFF0D0E12);

  /// Texto secundario en modo claro.
  static const Color textMutedLight = Color(0xFF73757F);

  // ----------------------------------------------------------
  // Colores semánticos
  // ----------------------------------------------------------

  /// Acción principal / acento de la app — azul grisáceo muted.
  static const Color primary = Color(0xFF6676A5);

  /// Foreground sobre primary (blanco sobre azul).
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Contenedor primario para fondos sutiles.
  static const Color primaryContainer = Color(0xFF465174);

  /// Foreground sobre primaryContainer.
  static const Color onPrimaryContainer = Color(0xFFC8D3FD);

  /// Color secundario / lavanda suave.
  static const Color secondary = Color(0xFFC1C6DD);

  /// Contenedor secundario.
  static const Color secondaryContainer = Color(0xFF353B4D);

  /// Ingresos / positivo — verde suave (menos agresivo que el neón anterior).
  static const Color income = Color(0xFF4CAF82);

  /// Gastos / negativo / destructivo — coral rojo suave.
  static const Color error = Color(0xFFFA746F);

  /// Foreground sobre error.
  static const Color onError = Color(0xFFFFFFFF);

  // ----------------------------------------------------------
  // Colores de categorías — Catpuccin Latte
  // ----------------------------------------------------------

  static const Color catRosewater = Color(0xFFDC8A78);
  static const Color catFlamingo = Color(0xFFDD7878);
  static const Color catPink = Color(0xFFEA76CB);
  static const Color catMauve = Color(0xFF8839EF);
  static const Color catRed = Color(0xFFD20F39);
  static const Color catMaroon = Color(0xFFE64553);
  static const Color catPeach = Color(0xFFFE640B);
  static const Color catYellow = Color(0xFFDF8E1D);
  static const Color catGreen = Color(0xFF40A02B);
  static const Color catTeal = Color(0xFF179299);
  static const Color catSky = Color(0xFF04A5E5);
  static const Color catSapphire = Color(0xFF209FB5);
  static const Color catBlue = Color(0xFF1E66F5);
  static const Color catLavender = Color(0xFF7287FD);

  /// Lista ordenada de los 14 colores Catpuccin Latte para el color picker.
  static const List<Color> categoryPresets = [
    catBlue,
    catSapphire,
    catSky,
    catTeal,
    catGreen,
    catYellow,
    catPeach,
    catMaroon,
    catRed,
    catPink,
    catMauve,
    catLavender,
    catFlamingo,
    catRosewater,
  ];
}
