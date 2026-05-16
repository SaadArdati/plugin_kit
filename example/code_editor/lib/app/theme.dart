/// JetBrains "Islands Dark" inspired Material 3 theme for the code editor
/// example.
///
/// The entire visual identity (colors, typography, component shapes,
/// densities) is configured inside the [ThemeData] constructor returned by
/// [editorTheme]. Consumers read through `Theme.of(context)` only — there
/// are no exported tokens, getters, or static color classes.
library;

import 'package:flutter/material.dart';

/// Builds the Islands-Dark Material 3 theme used by the code editor shell.
ThemeData editorTheme() {
  const colorScheme = ColorScheme.dark(
    primary: Color(0xFF3574F0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF2E5AAC),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFF6F737A),
    onSecondary: Color(0xFFFFFFFF),
    tertiary: Color(0xFF57A64A),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFF1E1F22),
    onSurface: Color(0xFFBCBEC4),
    onSurfaceVariant: Color(0xFF8C8F94),
    surfaceContainerLowest: Color(0xFF1A1B1E),
    surfaceContainerLow: Color(0xFF26282B),
    surfaceContainer: Color(0xFF2B2D30),
    surfaceContainerHigh: Color(0xFF313335),
    surfaceContainerHighest: Color(0xFF393B40),
    outline: Color(0xFF393B40),
    outlineVariant: Color(0xFF2F3133),
    error: Color(0xFFE55765),
    onError: Color(0xFFFFFFFF),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 13, height: 1.5),
      bodyMedium: TextStyle(fontSize: 12, height: 1.4),
      bodySmall: TextStyle(fontSize: 11, height: 1.3),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.primary,
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      dividerColor: colorScheme.outlineVariant,
      indicator: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.primary, width: 2)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 16,
        minimumSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      textStyle: TextStyle(fontSize: 11, color: colorScheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      waitDuration: const Duration(milliseconds: 600),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(strokeWidth: 2),
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 4,
      minLeadingWidth: 16,
    ),
  );
}
