/// Builds the host-app override of `PluginKitVisualsPlugin` for the editor's
/// five UI plugins. Carries the label, description, icon, and accent color
/// for each one. Read by the chip row (`PluginKitVisualsPlugin.visualFor`)
/// and by `showPluginKitDialog`'s Plugins tab.
///
/// Behavior-only plugins (linter, formatters, language pipelines) intentionally
/// have no visual — they are invisible in the chip row and show up in the
/// dialog with derived defaults.
library;

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

import 'plugins/ai_assist_plugin.dart';
import 'plugins/git_plugin.dart';
import 'plugins/minimap_plugin.dart';
import 'plugins/runner_plugin.dart';
import 'plugins/terminal_plugin.dart';

/// Returns the visuals plugin attached to the editor's runtime.
Plugin editorVisualsPlugin() => PluginKitVisualsPlugin(
  pluginVisuals: const {
    RunnerPlugin.id: PluginKitVisual(
      label: 'Runner',
      description:
          'Runs the current document and streams output to a console panel.',
      icon: Icon(Icons.play_arrow),
      color: Color(0xFF57A64A),
    ),
    GitPlugin.id: PluginKitVisual(
      label: 'Git',
      description: 'Shows working-tree changes and stages a fake commit.',
      icon: Icon(Icons.commit),
      color: Color(0xFFE8A736),
    ),
    TerminalPlugin.id: PluginKitVisual(
      label: 'Terminal',
      description:
          'Bottom-panel shell that pipes `dart`, `git`, `ls` and friends to mock output.',
      icon: Icon(Icons.terminal),
      color: Color(0xFF56B6C2),
    ),
    AiAssistPlugin.id: PluginKitVisual(
      label: 'AI Assist',
      description:
          'Vendor-branded chat surface — fake-streams responses to demo a branded plugin.',
      icon: Icon(Icons.auto_awesome),
      color: Color(0xFF8B7BFF),
    ),
    MinimapPlugin.id: PluginKitVisual(
      label: 'Minimap',
      description:
          'Renders a syntax-tinted overview of the active document on the right rail.',
      icon: Icon(Icons.map_outlined),
      color: Color(0xFF548AF7),
    ),
  },
);
