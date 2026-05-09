/// JetBrains Islands Dark inspired color palette and text styles.
///
/// Centralized theme tokens so NO hard-coded colors exist in plugin panels
/// or the shell. Every visual element pulls from here.
library;

import 'package:flutter/material.dart';

abstract final class EditorColors {
  // Backgrounds, layered from deepest to most elevated.
  static const canvas = Color(0xFF1E1F22); // Deepest background
  static const surface = Color(0xFF2B2D30); // Panel/toolbar surfaces
  static const surfaceHigh = Color(0xFF313335); // Elevated: tab bars, headers
  static const surfaceBright = Color(
    0xFF393B40,
  ); // Highest: hover, active states

  // Editor
  static const editorBg = Color(0xFF1E1F22);
  static const editorText = Color(0xFFBCBEC4);
  static const editorGutter = Color(0xFF2B2D30);

  // Borders
  static const border = Color(0xFF393B40);
  static const borderSubtle = Color(0xFF2F3133);

  // Accent: JetBrains blue.
  static const accent = Color(0xFF3574F0);
  static const accentMuted = Color(0xFF2E5AAC);

  // Text hierarchy
  static const textPrimary = Color(0xFFBCBEC4);
  static const textSecondary = Color(0xFF6F737A);
  static const textMuted = Color(0xFF55575E);
  static const textOnAccent = Color(0xFFFFFFFF);

  // Semantic
  static const success = Color(0xFF57A64A);
  static const warning = Color(0xFFE8A736);
  static const error = Color(0xFFE55765);
  static const info = Color(0xFF548AF7);

  // Syntax (for minimap)
  static const syntaxComment = Color(0xFF7A7E85);
  static const syntaxKeyword = Color(0xFFCF8E6D);
  static const syntaxString = Color(0xFF6AAB73);
  static const syntaxType = Color(0xFF56A8F5);
  static const syntaxFunction = Color(0xFF56B6C2);
  static const syntaxNumber = Color(0xFF2AACB8);
  static const syntaxImport = Color(0xFFC77DBB);
  static const syntaxBrace = Color(0xFF4E5157);
  static const syntaxDefault = Color(0xFF8C8F94);

  // Interactive states
  static const hoverOverlay = Color(0x0FFFFFFF); // 6% white
  static const activeOverlay = Color(0x1AFFFFFF); // 10% white
  static const selectedChip = Color(0xFF2E5AAC);
}

abstract final class EditorTextStyles {
  static const mono12 = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    color: EditorColors.editorText,
  );

  static const mono13 = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.6,
    color: EditorColors.editorText,
  );

  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: EditorColors.textSecondary,
  );

  static const panelTitle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: EditorColors.textSecondary,
  );

  static const statusBar = TextStyle(
    fontSize: 11,
    color: EditorColors.textSecondary,
  );

  static const tabActive = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: EditorColors.textPrimary,
  );

  static const tabInactive = TextStyle(
    fontSize: 12,
    color: EditorColors.textMuted,
  );
}

abstract final class EditorDecorations {
  static final panelBorder = Border.all(color: EditorColors.borderSubtle);

  static final panelRadius = BorderRadius.circular(8);

  static BoxDecoration panelBox({Color? color}) => BoxDecoration(
    color: color ?? EditorColors.canvas,
    borderRadius: panelRadius,
    border: panelBorder,
  );
}
