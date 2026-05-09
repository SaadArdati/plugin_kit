import 'package:flutter/material.dart';

import 'plugin_kit_dialog_tokens.dart';

/// Convenience accessors for chrome the dialog reads off the host's theme.
///
/// Internal to the dialog package. Hidden from the public barrel so hosts
/// don't grow a dependency on this getter shape.
extension PluginKitDialogThemeData on ThemeData {
  /// Card corner radius read from [CardTheme.shape], falling back to
  /// [kCardRadius] when the host has supplied a non-`RoundedRectangleBorder`
  /// (e.g. `StadiumBorder`) or a directional `BorderRadiusGeometry`. The
  /// canonical [buildPluginKitDialogDarkTheme] always supplies a
  /// `RoundedRectangleBorder`, so the fallback only kicks in for hosts with
  /// custom card themes.
  BorderRadius get cardBorderRadius {
    final shape = cardTheme.shape;
    if (shape is RoundedRectangleBorder) {
      final radius = shape.borderRadius;
      if (radius is BorderRadius) return radius;
    }
    return kCardRadius;
  }
}

/// Domain-semantic accent colors that the host's `ThemeData` can't supply.
///
/// Material's `ColorScheme` covers chrome (surfaces, outlines, typography),
/// but it has no concept of "stable plugin", "experimental plugin", or
/// "agent-config" - these are plugin_kit_dialog domain meanings. This
/// extension carries only those irreducible accents; everything else
/// (radii, paddings, text styles, badge surfaces, JSON-preview surfaces) is
/// derived from `Theme.of(context)` so the dialog adapts to whatever theme
/// the host is using.
class PluginKitDialogTheme extends ThemeExtension<PluginKitDialogTheme> {
  /// Accent for stable plugin UI affordances.
  final Color stableAccent;

  /// Accent for experimental plugin UI affordances and unsaved badges.
  final Color experimentalAccent;

  /// Accent for agent-configuration affordances.
  final Color agentAccent;

  /// Background tint for the active-stat icon chip.
  final Color statActiveBackground;

  /// Background tint for the stable-stat icon chip.
  final Color statStableBackground;

  /// Background tint for the experimental-stat icon chip.
  final Color statExperimentalBackground;

  /// Creates a dialog theme extension with the six semantic accent slots.
  const PluginKitDialogTheme({
    required this.stableAccent,
    required this.experimentalAccent,
    required this.agentAccent,
    required this.statActiveBackground,
    required this.statStableBackground,
    required this.statExperimentalBackground,
  });

  @override
  PluginKitDialogTheme copyWith({
    Color? stableAccent,
    Color? experimentalAccent,
    Color? agentAccent,
    Color? statActiveBackground,
    Color? statStableBackground,
    Color? statExperimentalBackground,
  }) {
    return PluginKitDialogTheme(
      stableAccent: stableAccent ?? this.stableAccent,
      experimentalAccent: experimentalAccent ?? this.experimentalAccent,
      agentAccent: agentAccent ?? this.agentAccent,
      statActiveBackground: statActiveBackground ?? this.statActiveBackground,
      statStableBackground: statStableBackground ?? this.statStableBackground,
      statExperimentalBackground:
          statExperimentalBackground ?? this.statExperimentalBackground,
    );
  }

  @override
  PluginKitDialogTheme lerp(
    ThemeExtension<PluginKitDialogTheme>? other,
    double t,
  ) {
    if (other is! PluginKitDialogTheme) return this;
    return PluginKitDialogTheme(
      stableAccent: Color.lerp(stableAccent, other.stableAccent, t)!,
      experimentalAccent: Color.lerp(
        experimentalAccent,
        other.experimentalAccent,
        t,
      )!,
      agentAccent: Color.lerp(agentAccent, other.agentAccent, t)!,
      statActiveBackground: Color.lerp(
        statActiveBackground,
        other.statActiveBackground,
        t,
      )!,
      statStableBackground: Color.lerp(
        statStableBackground,
        other.statStableBackground,
        t,
      )!,
      statExperimentalBackground: Color.lerp(
        statExperimentalBackground,
        other.statExperimentalBackground,
        t,
      )!,
    );
  }

  /// Default dark variant matching the screenshots.
  static PluginKitDialogTheme dark() {
    return const PluginKitDialogTheme(
      stableAccent: kStableGreen,
      experimentalAccent: kExperimentalOrange,
      agentAccent: kAgentPurple,
      statActiveBackground: kStatActiveBg,
      statStableBackground: kStatStableBg,
      statExperimentalBackground: kStatExperimentalBg,
    );
  }

  /// Default light variant.
  static PluginKitDialogTheme light() {
    return const PluginKitDialogTheme(
      stableAccent: kStableGreen,
      experimentalAccent: kExperimentalOrange,
      agentAccent: kAgentPurple,
      statActiveBackground: Color(0x1A3B82F6),
      statStableBackground: Color(0x1A22C55E),
      statExperimentalBackground: Color(0x1AF59E0B),
    );
  }

  /// Helper used by widgets when the host hasn't registered the
  /// extension. Picks dark/light by [Theme.of(context).brightness].
  static PluginKitDialogTheme of(BuildContext context) {
    return Theme.of(context).extension<PluginKitDialogTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? PluginKitDialogTheme.dark()
            : PluginKitDialogTheme.light());
  }
}
