import 'package:flutter/material.dart';

/// Base dialog/page background color token (Spec §8.3).
const kBackground = Color(0xFF1A1A1A);

/// Default card and panel background color token.
const kPanelBackground = Color(
  0xFF202022,
); // ~ Colors.white at 3% over kBackground

/// Hover-state panel background color token.
const kPanelBackgroundHover = Color(0xFF26262A);

/// Subtle panel border color token.
const kPanelBorder = Color(0x14FFFFFF); // 8% white

/// Stronger panel border color token.
const kPanelBorderStrong = Color(0x1FFFFFFF); // 12% white

/// Primary body/title text color token.
const kTextPrimary = Color(0xFFE5E7EB);

/// Secondary supporting text color token.
const kTextSecondary = Color(0xFF9CA3AF);

/// Muted helper/placeholder text color token.
const kTextMuted = Color(0xFF6B7280);

/// Primary action accent color token used by Save and active controls.
const kAccentBlue = Color(0xFF3B82F6); // primary, Save button

/// Accent color token for stable plugin states.
const kStableGreen = Color(0xFF22C55E);

/// Accent color token for experimental plugin states.
const kExperimentalOrange = Color(0xFFF59E0B);

/// Accent color token for agent-configuration highlights.
const kAgentPurple = Color(0xFFA855F7);

/// Tint color token for active-plugin stat icon backgrounds.
const kStatActiveBg = Color(0x803B82F6); // 50% accent

/// Tint color token for stable-plugin stat icon backgrounds.
const kStatStableBg = Color(0x8022C55E);

/// Tint color token for experimental-plugin stat icon backgrounds.
const kStatExperimentalBg = Color(0x80F59E0B);

/// Badge and chip background color token.
const kBadgeBg = Color(0xFF2A2A2E);

/// Badge and chip border color token.
const kBadgeBorder = Color(0x29FFFFFF); // 16% white

/// Background color token for locked/disabled chips.
const kLockedChipBg = Color(0xFF202022);

/// Background color token for the JSON preview/editor surface.
const kJsonPreviewBg = Color(0xFF18181B);

/// Border color token for the JSON preview/editor surface.
const kJsonPreviewBorder = Color(0x29FFFFFF);

/// Error color token for invalid JSON states.
const kJsonPreviewError = Color(0xFFEF4444);

/// Standard corner radius token for cards and text fields.
const kCardRadius = BorderRadius.all(Radius.circular(12));

/// Standard interior padding token for dialog cards.
const kCardPadding = EdgeInsets.all(24);

/// Standard vertical spacing token between major sections.
const kSectionGap = EdgeInsets.only(top: 16);
