part of '../plugin.dart';

extension _RuntimeDispose<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
>
    on PluginRuntime<G, S> {
  Future<void> _disposeImpl() async {
    if (_disposed) return;
    if (!_initialized) {
      _disposed = true;
      return;
    }

    final detachErrors = <(PluginId, Object, StackTrace)>[];

    // Per-session dispose runs even when one session's detach throws. The
    // previous behavior propagated the first session.dispose() throw and
    // aborted the loop, leaving every later session attached forever.
    for (final session in [..._sessions]) {
      try {
        await session.dispose();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        if (e is PluginLifecycleException) {
          // Already a structured aggregate; flatten into our combined list
          // so the caller sees one PluginLifecycleException at the end with
          // every per-plugin failure across both global and session scopes.
          for (final inner in e.failures) {
            detachErrors.add(inner);
          }
        } else {
          _runtimeLog.severe(
            'Failed to dispose session during runtime dispose',
            e,
            st,
          );
          // No PluginId to attribute this to; use a sentinel id.
          detachErrors.add((const PluginId('<session>'), e, st));
        }
      }
    }

    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          await plugin._runDetach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          detachErrors.add((plugin.pluginId, e, st));
        }
      }
    }
    globalBus.dispose();
    _enabledGlobalPluginIds.clear();
    await _settingsController.close();
    _initialized = false;
    _disposed = true;

    if (detachErrors.isNotEmpty) {
      _runtimeLog.warning(
        'Runtime disposed with ${detachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('detachGlobal', detachErrors);
    }
    _runtimeLog.info('Runtime disposed');
  }
}
