// ============================================================
// Tema de la aplicación — Material Design 3
// ============================================================
//
// Flutter 3+ usa Material 3 por defecto. El sistema de colores
// se genera automáticamente a partir de un "seed color" usando
// el algoritmo HCT de Google. Eso garantiza accesibilidad y
// armonía cromática en todos los roles de color.

import 'package:flutter/material.dart';

class AppTheme {
  // Constructor privado: esta clase sólo tiene métodos estáticos.
  AppTheme._();

  /// Color semilla: teal financiero.
  /// Flutter genera toda la paleta (primary, secondary, surface, error, etc.)
  /// a partir de este único color usando el algoritmo Material You.
  static const Color _seedColor = Color(0xFF00897B);

  /// Tema claro.
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      // AppBar sin elevación, fusionado con el fondo para aspecto moderno.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),

      // Cards con esquinas redondeadas y sombra sutil.
      // En Flutter 3.x ThemeData.cardTheme acepta CardThemeData.
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        // El color lo hereda del colorScheme (surfaceContainerLow)
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // NavigationBar de Material 3 (la barra inferior de tabs).
      navigationBarTheme: NavigationBarThemeData(
        // Sin fondo de indicador extra — el tab activo se destaca con el
        // color del icono y texto, no con un rectángulo de fondo llamativo.
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // FAB redondeado por defecto en M3.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),

      // Chips usados en la pantalla de categorías.
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Tema oscuro — mismo seed color, brillo invertido.
  /// Flutter ajusta automáticamente los roles de color para el modo oscuro.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),

      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
