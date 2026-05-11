/// Flutter-aware factory abstracts for plugin UI contributions.
///
/// Plugins register concrete implementations of these in the
/// ServiceRegistry. The shell resolves them by panel/action ID
/// to render plugin-controlled widgets.
library;

import 'package:flutter/widgets.dart';

/// Factory that builds the widget content for a contributed panel.
///
/// The shell provides the panel frame (title bar, collapse/expand).
/// The factory controls everything inside, so plugins have full creative
/// freedom over colors and layout.
// #docregion factories-panel-widget-factory
abstract class PanelWidgetFactory {
  Widget build(BuildContext context);
}
// #enddocregion factories-panel-widget-factory
