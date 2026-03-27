import 'package:flutter/material.dart';

const kThemeModePrefKey = 'app.theme_mode';

const kThemeModeSystemValue = 'system';
const kThemeModeDarkValue = 'dark';
const kThemeModeLightValue = 'light';

enum AppThemePreference { system, dark, light }

const kInitialThemePreference = AppThemePreference.system;

AppThemePreference parseAppThemePreference(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case kThemeModeDarkValue:
      return AppThemePreference.dark;
    case kThemeModeLightValue:
      return AppThemePreference.light;
    case kThemeModeSystemValue:
    default:
      return AppThemePreference.system;
  }
}

String appThemePreferenceToStorage(AppThemePreference preference) {
  switch (preference) {
    case AppThemePreference.system:
      return kThemeModeSystemValue;
    case AppThemePreference.dark:
      return kThemeModeDarkValue;
    case AppThemePreference.light:
      return kThemeModeLightValue;
  }
}

ThemeMode appThemePreferenceToThemeMode(AppThemePreference preference) {
  switch (preference) {
    case AppThemePreference.system:
      return ThemeMode.system;
    case AppThemePreference.dark:
      return ThemeMode.dark;
    case AppThemePreference.light:
      return ThemeMode.light;
  }
}

String appThemePreferenceLabel(AppThemePreference preference) {
  switch (preference) {
    case AppThemePreference.system:
      return 'Sistema';
    case AppThemePreference.dark:
      return 'Oscuro';
    case AppThemePreference.light:
      return 'Claro';
  }
}
