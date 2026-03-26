// ============================================================
// Tema de la aplicación — Design System "Premium Fintech Muted Blue"
// ============================================================
//
// Dark-first: el tema oscuro replica el diseño de Stitch.
// El tema claro usa los mismos tokens adaptados a superficies claras.
//
// Tipografía: IBM Plex Sans en todos los roles (headings, body, números).
//
// Border radius: 8px small / 16px medium (redondeado profesional) /
//                32px large / full pill.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // ----------------------------------------------------------
  // Radios reutilizables
  // ----------------------------------------------------------
  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMedium = BorderRadius.all(
    Radius.circular(16),
  );
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(32));
  static const BorderRadius radiusFull = BorderRadius.all(
    Radius.circular(9999),
  );

  // ----------------------------------------------------------
  // Tema oscuro
  // ----------------------------------------------------------
  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      surface: AppColors.surfaceDark,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.secondary,
      tertiary: AppColors.secondary,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: AppColors.secondaryContainer,
      onTertiaryContainer: AppColors.secondary,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: Color(0xFF3D1010),
      onErrorContainer: AppColors.error,
      onSurface: AppColors.textPrimaryDark,
      onSurfaceVariant: AppColors.textMutedDark,
      surfaceContainerHighest: AppColors.surfaceBrightDark,
      surfaceContainerHigh: AppColors.surfaceElevatedDark,
      surfaceContainer: AppColors.surfaceContainerDark,
      surfaceContainerLow: AppColors.surfaceDark,
      surfaceContainerLowest: AppColors.backgroundDark,
      outline: AppColors.surfaceElevatedDark,
      outlineVariant: Color(0xFF464750),
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
      surfaceContainer: AppColors.surfaceContainerDark,
      surfaceElevated: AppColors.surfaceElevatedDark,
      textPrimary: AppColors.textPrimaryDark,
      textMuted: AppColors.textMutedDark,
    );
  }

  // ----------------------------------------------------------
  // Tema claro
  // ----------------------------------------------------------
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: Color(0xFFD6DCFA),
      onPrimaryContainer: Color(0xFF1A2550),
      secondary: AppColors.primary,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: Color(0xFFDDE1F9),
      onSecondaryContainer: Color(0xFF1A2550),
      tertiary: AppColors.primary,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: Color(0xFFDDE1F9),
      onTertiaryContainer: Color(0xFF1A2550),
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: Color(0xFFFFDADE),
      onErrorContainer: Color(0xFF400014),
      onSurface: AppColors.textPrimaryLight,
      onSurfaceVariant: AppColors.textMutedLight,
      surfaceContainerHighest: AppColors.surfaceElevatedLight,
      surfaceContainerHigh: AppColors.surfaceElevatedLight,
      surfaceContainer: AppColors.surfaceContainerLight,
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
      surfaceContainer: AppColors.surfaceContainerLight,
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
    required Color surfaceContainer,
    required Color surfaceElevated,
    required Color textPrimary,
    required Color textMuted,
  }) {
    // IBM Plex Sans en todos los roles tipográficos.
    final t = GoogleFonts.ibmPlexSansTextTheme().copyWith(
      displayLarge: GoogleFonts.ibmPlexSans(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
        color: textPrimary,
      ),
      displayMedium: GoogleFonts.ibmPlexSans(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: textPrimary,
      ),
      displaySmall: GoogleFonts.ibmPlexSans(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineLarge: GoogleFonts.ibmPlexSans(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineMedium: GoogleFonts.ibmPlexSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineSmall: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: GoogleFonts.ibmPlexSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleSmall: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: textMuted,
      ),
      bodyLarge: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      ),
      bodyMedium: GoogleFonts.ibmPlexSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      ),
      bodySmall: GoogleFonts.ibmPlexSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textMuted,
      ),
      labelLarge: GoogleFonts.ibmPlexSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      labelMedium: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textMuted,
      ),
      labelSmall: GoogleFonts.ibmPlexSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: textMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: t,

      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: radiusMedium),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return IconThemeData(color: textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.ibmPlexSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            );
          }
          return GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: textMuted,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusFull),
      ),

      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: radiusFull),
        backgroundColor: surfaceElevated,
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        border: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide.none,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.ibmPlexSans(fontSize: 14, color: textMuted),
        labelStyle: GoogleFonts.ibmPlexSans(fontSize: 14, color: textMuted),
      ),

      dividerTheme: DividerThemeData(
        color: surfaceElevated,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: textMuted,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: surfaceElevated,
          disabledForegroundColor: textMuted,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: radiusFull),
          textStyle: GoogleFonts.ibmPlexSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size.fromHeight(52),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: const RoundedRectangleBorder(borderRadius: radiusMedium),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          color: textPrimary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: radiusMedium),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
