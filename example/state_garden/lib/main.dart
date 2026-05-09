import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:state_garden/state_garden.dart';

void main() => runApp(const PluginKitStateProofsApp());

/// Boots a single [PluginRuntime] and one [PluginSession], wires
/// them into the three locators each integration expects (Provider override
/// for Riverpod, GetIt for the GetIt screen, direct injection for the
/// rest), and renders the launcher.
class PluginKitStateProofsApp extends StatefulWidget {
  const PluginKitStateProofsApp({super.key});

  @override
  State<PluginKitStateProofsApp> createState() =>
      _PluginKitStateProofsAppState();
}

class _PluginKitStateProofsAppState extends State<PluginKitStateProofsApp> {
  RuntimeHolder? _holder;
  final GetIt _locator = GetIt.asNewInstance();

  @override
  void initState() {
    super.initState();
    RuntimeHolder.create().then((RuntimeHolder holder) {
      if (!mounted) {
        unawaited(holder.dispose());
        return;
      }
      _locator.registerSingleton<PluginSession>(holder.session);
      setState(() => _holder = holder);
    });
  }

  @override
  void dispose() {
    final RuntimeHolder? holder = _holder;
    _holder = null;
    if (holder != null) unawaited(holder.dispose());
    unawaited(_locator.reset());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RuntimeHolder? holder = _holder;
    if (holder == null) return const _LoadingApp();
    return ProviderScope(
      overrides: <Override>[sessionProvider.overrideWithValue(holder.session)],
      child: MaterialApp(
        title: 'plugin_kit state proofs',
        home: IntegrationLauncher(session: holder.session, locator: _locator),
      ),
    );
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
