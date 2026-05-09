import 'package:flutter/material.dart';

import 'plugin_kit_dialog_theme.dart';
import 'plugin_kit_dialog_tokens.dart';

/// Builds the default dark `ThemeData` for the dialog package (Spec §8.2).
ThemeData buildPluginKitDialogDarkTheme() {
  const colorScheme = ColorScheme.dark(
    primary: kAccentBlue,
    onPrimary: Colors.white,
    surface: kBackground,
    surfaceContainerLowest: kJsonPreviewBg,
    surfaceContainerHigh: kPanelBackground,
    surfaceContainerHighest: kBadgeBg,
    onSurface: kTextPrimary,
    onSurfaceVariant: kTextSecondary,
    outline: kPanelBorderStrong,
    outlineVariant: kPanelBorder,
    error: kJsonPreviewError,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kBackground,
    dividerColor: kPanelBorder,
    textTheme: _buildDarkTextTheme(),
    inputDecorationTheme: _buildDarkInputDecorationTheme(),
    switchTheme: _buildSwitchTheme(colorScheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccentBlue,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: kCardRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kTextPrimary,
        side: const BorderSide(color: kPanelBorderStrong),
        shape: const RoundedRectangleBorder(borderRadius: kCardRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: kPanelBackground,
      selectedColor: kStatActiveBg,
      disabledColor: kLockedChipBg,
      side: BorderSide(color: kPanelBorder),
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: kTextPrimary),
      secondaryLabelStyle: TextStyle(color: kTextPrimary),
      brightness: Brightness.dark,
      padding: EdgeInsets.symmetric(horizontal: 8),
    ),
    cardTheme: const CardThemeData(
      color: kPanelBackground,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: kCardRadius,
        side: BorderSide(color: kPanelBorder),
      ),
    ),
  );

  return base.copyWith(extensions: [PluginKitDialogTheme.dark()]);
}

/// Builds the default light `ThemeData` for the dialog package (Spec §8.2).
ThemeData buildPluginKitDialogLightTheme() {
  const lightBackground = Color(0xFFF5F6F8);
  const lightPanelBackground = Color(0xFFFFFFFF);
  const lightPanelBorder = Color(0x1F000000);
  const lightPanelBorderStrong = Color(0x29000000);
  const lightTextPrimary = Color(0xFF111827);

  const colorScheme = ColorScheme.light(
    primary: kAccentBlue,
    onPrimary: Colors.white,
    surface: lightBackground,
    surfaceContainerLowest: Color(0xFFF9FAFB),
    surfaceContainerHigh: lightPanelBackground,
    surfaceContainerHighest: Color(0xFFF3F4F6),
    onSurface: lightTextPrimary,
    onSurfaceVariant: Color(0xFF4B5563),
    outline: lightPanelBorderStrong,
    outlineVariant: lightPanelBorder,
    error: kJsonPreviewError,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: lightBackground,
    dividerColor: lightPanelBorder,
    textTheme: _buildLightTextTheme(),
    inputDecorationTheme: _buildLightInputDecorationTheme(),
    switchTheme: _buildSwitchTheme(colorScheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccentBlue,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: kCardRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightTextPrimary,
        side: const BorderSide(color: lightPanelBorderStrong),
        shape: const RoundedRectangleBorder(borderRadius: kCardRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFFF3F4F6),
      selectedColor: Color(0x1A3B82F6),
      disabledColor: Color(0xFFE5E7EB),
      side: BorderSide(color: lightPanelBorder),
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: lightTextPrimary),
      secondaryLabelStyle: TextStyle(color: lightTextPrimary),
      brightness: Brightness.light,
      padding: EdgeInsets.symmetric(horizontal: 8),
    ),
    cardTheme: const CardThemeData(
      color: lightPanelBackground,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: kCardRadius,
        side: BorderSide(color: lightPanelBorder),
      ),
    ),
  );

  return base.copyWith(extensions: [PluginKitDialogTheme.light()]);
}

/// Switch theme used by `CompactSwitch`. Drifts the unselected thumb to
/// `onSurfaceVariant` and the unselected track outline to `outlineVariant`
/// so they read as muted chrome rather than full-strength outline.
SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return null;
      return colorScheme.onSurfaceVariant;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return null;
      return colorScheme.outlineVariant;
    }),
  );
}

TextTheme _buildDarkTextTheme() {
  return const TextTheme(
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: kTextPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    bodyLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: kTextPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: kTextSecondary,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: kTextMuted,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: kTextPrimary,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
  );
}

TextTheme _buildLightTextTheme() {
  return const TextTheme(
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Color(0xFF111827),
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111827),
    ),
    bodyLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFF111827),
    ),
    bodyMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF4B5563),
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Color(0xFF6B7280),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111827),
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF1F2937),
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111827),
    ),
  );
}

InputDecorationTheme _buildDarkInputDecorationTheme() {
  return const InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: kPanelBackground,
    hintStyle: TextStyle(
      color: kTextMuted,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    labelStyle: TextStyle(
      color: kTextSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kPanelBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kPanelBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kAccentBlue),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kJsonPreviewError),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kJsonPreviewError),
    ),
  );
}

InputDecorationTheme _buildLightInputDecorationTheme() {
  return const InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    hintStyle: TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    labelStyle: TextStyle(
      color: Color(0xFF6B7280),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: Color(0x1F000000)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: Color(0x1F000000)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kAccentBlue),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kJsonPreviewError),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: kCardRadius,
      borderSide: BorderSide(color: kJsonPreviewError),
    ),
  );
}
