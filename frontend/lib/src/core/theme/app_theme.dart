// ============================================================
// Tema de la aplicación — Design System "Premium Fintech"
// ============================================================
//
// Dark-first: el tema oscuro replica el diseño de Stitch exactamente.
// El tema claro usa los mismos tokens adaptados a superficies claras.
//
// Tipografía:
//   - Outfit     → títulos / headings (reemplaza Clash Display)
//   - Inter      → cuerpo / labels (reemplaza Satoshi)
//   - Space Grotesk → cantidades / números
//
// Border radius: 4px base, 8px large (esquinas rectas — fintech premium).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // ----------------------------------------------------------
  // Radios reutilizables
  // ----------------------------------------------------------
  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusFull = BorderRadius.all(Radius.circular(9999));

  // ----------------------------------------------------------
  // Tema oscuro
  // ----------------------------------------------------------
  static ThemeData dark() {
    final colorScheme = const ColorScheme(
      brightness: Brightness.dark,
      // Fondos
      surface: AppColors.surfaceDark,
      // Primario
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.surfaceElevatedDark,
      onPrimaryContainer: AppColors.primary,
      // Secundario
      secondary: AppColors.accent,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.surfaceElevatedDark,
      onSecondaryContainer: AppColors.accent,
      // Terciario
      tertiary: AppColors.accent,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: AppColors.surfaceElevatedDark,
      onTertiaryContainer: AppColors.accent,
      // Error
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: Color(0xFF3D0016),
      onErrorContainer: AppColors.error,
      // Superficies
      onSurface: AppColors.textPrimaryDark,
      onSurfaceVariant: AppColors.textMutedDark,
      surfaceContainerHighest: AppColors.surfaceElevatedDark,
      surfaceContainerHigh: AppColors.surfaceElevatedDark,
      surfaceContainer: AppColors.surfaceDark,
      surfaceContainerLow: AppColors.surfaceDark,
      surfaceContainerLowest: AppColors.backgroundDark,
      // Outline
      outline: AppColors.surfaceElevatedDark,
      outlineVariant: AppColors.surfaceElevatedDark,
      // Misc
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: AppColors.textPrimaryDark,
      onInverseSurface: AppColors.backgroundDark,
      inversePrimary: AppColors.primary,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      background: AppColors.backgroundDark,
      surface: AppColors.surfaceDark,
      surfaceElevated: AppColors.surfaceElevatedDark,
      textPrimary: AppColors.textPrimaryDark,
      textMuted: AppColors.textMutedDark,
    );
  }

  // ----------------------------------------------------------
  // Tema claro
  // ----------------------------------------------------------
  static ThemeData light() {
    final colorScheme = const ColorScheme(
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: Color(0xFFD4FFE8),
      onPrimaryContainer: Color(0xFF003D1A),
      secondary: AppColors.accent,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: Color(0xFFD0F8FF),
      onSecondaryContainer: Color(0xFF003740),
      tertiary: AppColors.accent,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: Color(0xFFD0F8FF),
      onTertiaryContainer: Color(0xFF003740),
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: Color(0xFFFFDADE),
      onErrorContainer: Color(0xFF400014),
      onSurface: AppColors.textPrimaryLight,
      onSurfaceVariant: AppColors.textMutedLight,
      surfaceContainerHighest: AppColors.surfaceElevatedLight,
      surfaceContainerHigh: AppColors.surfaceElevatedLight,
      surfaceContainer: AppColors.surfaceLight,
      surfaceContainerLow: AppColors.surfaceLight,
      surfaceContainerLowest: AppColors.backgroundLight,
      outline: AppColors.surfaceElevatedLight,
      outlineVariant: AppColors.surfaceElevatedLight,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: AppColors.backgroundDark,
      onInverseSurface: AppColors.textPrimaryDark,
      inversePrimary: AppColors.primary,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      background: AppColors.backgroundLight,
      surface: AppColors.surfaceLight,
      surfaceElevated: AppColors.surfaceElevatedLight,
      textPrimary: AppColors.textPrimaryLight,
      textMuted: AppColors.textMutedLight,
    );
  }

  // ----------------------------------------------------------
  // Constructor interno compartido
  // ----------------------------------------------------------
  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color background,
    required Color surface,
    required Color surfaceElevated,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final baseTextTheme = GoogleFonts.interTextTheme().copyWith(
      // Títulos de pantalla y AppBar → Outfit
      displayLarge: GoogleFonts.outfit(fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: -1, color: textPrimary),
      displayMedium: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: textPrimary),
      displaySmall: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w500, color: textPrimary),
      headlineLarge: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
      headlineMedium: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      headlineSmall: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
      // Subtítulos
      titleLarge: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
      titleSmall: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: textMuted),
      // Cuerpo
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary),
      bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: textMuted),
      // Labels
      labelLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
      labelMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: textMuted),
      labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: baseTextTheme,

      // AppBar sin elevación, fondo = background para aspecto inmersivo.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      // Cards con esquinas rectas y color de superficie.
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: const RoundedRectangleBorder(borderRadius: radiusSmall),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // NavigationBar: fondo de superficie, indicador primario translúcido.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.primary);
          }
          return IconThemeData(color: textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            );
          }
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: textMuted,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // FAB: verde primario con foreground negro.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
      ),

      // Chips con esquinas pequeñas.
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: radiusSmall),
        backgroundColor: surfaceElevated,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
      ),

      // Inputs: fondo elevado, sin borde por defecto, 4px radius.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.primary, width: 1),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: textMuted),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: textMuted),
      ),

      // Dividers sutiles.
      dividerTheme: DividerThemeData(
        color: surfaceElevated,
        thickness: 1,
        space: 1,
      ),

      // ListTile sin padding extra — se controla en cada widget.
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: textMuted,
      ),

      // ElevatedButton → botón principal sólido.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: radiusSmall),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          minimumSize: const Size.fromHeight(52),
        ),
      ),

      // TextButton → acciones secundarias.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radiusSmall),
        ),
      ),

      // SnackBar.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: radiusMedium),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
