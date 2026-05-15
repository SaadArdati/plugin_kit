import 'package:flutter/widgets.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'session_scope.dart';

/// Imperative `State` mixin that subscribes to a [PluginSession]
/// event bus and re-attaches its subscriptions whenever the session
/// changes.
///
/// Bindings are registered via [listen] and [rebuildOn]. Both are
/// callable from any lifecycle callback, including [State.initState];
/// they only append to an internal descriptor list and the mixin
/// activates them when a session becomes available.
///
/// Different shape from the pure-Dart sibling. Despite the similar
/// name, this is *not* a Flutter wrapper around
/// `PluginSessionListener` in `package:plugin_kit`. The pure-Dart mixin
/// exposes a declarative `subscriptions` getter (a
/// `List<EventBinding>`) that the host materializes via
/// `attachSubscriptions()` / `detachSubscriptions()`. This mixin
/// exposes an imperative `listen<E>(handler)` API tied to the
/// `State<W>` lifecycle. They share `EventBinding` as the underlying
/// descriptor type but the call sites do not look the same. Pick the
/// shape that matches your host: a `State` reaches for this mixin; a
/// Cubit / `ChangeNotifier` / plain controller reaches for the
/// pure-Dart one.
///
/// The default [session] getter resolves the ambient
/// [PluginSessionScope]. When that scope's session changes (async
/// creation, parent rebuild with a new explicit session), the mixin's
/// [State.didChangeDependencies] cancels active subscriptions and
/// re-attaches them against the new session. When the host overrides
/// [session] to read from `widget` (e.g. `=> widget.session`), parent
/// rebuilds with a different `widget.session` are picked up via
/// [State.didUpdateWidget].
///
/// ```dart
/// class _ChatState extends State<ChatScreen>
///     with PluginSessionStateListener<ChatScreen> {
///   String? _last;
///
///   @override
///   void initState() {
///     super.initState();
///     listen<ChatMessageReceived>((envelope) {
///       setState(() => _last = envelope.event.text);
///     });
///   }
/// }
/// ```
///
/// Handler bodies are skipped after the state is disposed, so user code
/// does not need a `mounted` guard inside [listen].
mixin PluginSessionStateListener<W extends StatefulWidget> on State<W> {
  /// The session whose bus this state listens to. Defaults to the
  /// nearest enclosing [PluginSessionScope]; override to point at a
  /// session resolved differently (typically `widget.session`).
  ///
  /// Returns `null` when the ambient scope has not yet finished
  /// creating its session (a normal transient state during async
  /// session creation). Returns non-null when a session is available.
  ///
  /// Throws [FlutterError] when no [PluginSessionScope] ancestor exists
  /// AND the consuming state has not overridden this getter. The error
  /// message lists both fixes.
  PluginSession? get session {
    if (context.findAncestorWidgetOfExactType<PluginSessionScope>() == null) {
      throw FlutterError(
        'PluginSessionStateListener default `session` getter on $runtimeType '
        'could not find a PluginSessionScope ancestor.\n'
        'Either wrap an ancestor in PluginSessionScope, or override '
        '`PluginSession? get session` on $runtimeType to provide a session '
        'directly (e.g., `=> widget.session`).',
      );
    }
    return PluginSessionScope.maybeOf(context);
  }

  /// Attach closures: each `listen` / `rebuildOn` call adds one. When a
  /// session is available, each attach creates a fresh subscription, wraps
  /// its handler with a generation guard, and returns the subscription so
  /// the mixin can cancel it on swap/dispose.
  final List<EventSubscription Function(PluginSession, int)> _attachers = [];
  final List<EventSubscription> _activeSubs = [];
  PluginSession? _currentSession;

  /// Bumped on every session swap. A handler closure captures the value
  /// AT ATTACH TIME and compares against the current value at invocation.
  /// When they differ, the handler is being called by a stale dispatch
  /// from the previous session (an emit that started before the swap and
  /// completed after) and is dropped. Without this guard, an in-flight
  /// emit on the old session would still deliver to the widget bound to
  /// the new session and corrupt its state.
  int _attachGeneration = 0;

  /// Subscribe to events of type [E] on the current session. The
  /// subscription is re-attached automatically across session swaps and
  /// cancelled in [dispose]. Late envelopes from a previous session are
  /// dropped after a swap.
  ///
  /// Callable from any lifecycle callback, including [State.initState].
  ///
  /// The handler receives the full [EventEnvelope], so envelope context
  /// like `identifier` and `stopped` stays reachable. Read the payload
  /// via `envelope.event`.
  ///
  /// [priority] and [identifier] map directly to [EventBus.on]; see
  /// that method for the dispatch model.
  void listen<E>(
    void Function(EventEnvelope<E> envelope) handler, {
    int priority = 0,
    String? identifier,
  }) {
    EventSubscription attach(PluginSession session, int boundGen) {
      final binding = EventBinding.on<E>(
        (envelope) {
          if (!mounted) return;
          if (boundGen != _attachGeneration) return;
          handler(envelope);
        },
        priority: priority,
        identifier: identifier,
      );
      return binding.attachTo(session);
    }

    _attachers.add(attach);
    final current = _currentSession;
    if (current != null) {
      _activeSubs.add(attach(current, _attachGeneration));
    }
  }

  /// Rebuild the state on every event of type [E] that satisfies [when]
  /// (when [when] is null, every event of type [E]). The binding is
  /// re-attached automatically across session swaps and cancelled in
  /// [dispose].
  ///
  /// The [when] predicate receives the full [EventEnvelope] so it can
  /// gate the rebuild on envelope context (for example `identifier` or
  /// `stopped`) in addition to the payload.
  ///
  /// For unfiltered rebuild-on-event, prefer [BuildContext.watchEvent]
  /// directly. It uses InheritedWidget-style dependency attachment and
  /// needs no State mixin. Use [rebuildOn] when you need a [when]
  /// predicate to gate the rebuild itself.
  void rebuildOn<E>([bool Function(EventEnvelope<E> envelope)? when]) {
    EventSubscription attach(PluginSession session, int boundGen) {
      final binding = EventBinding.on<E>((envelope) {
        if (!mounted) return;
        if (boundGen != _attachGeneration) return;
        if (when != null && !when(envelope)) return;
        setState(() {});
      });
      return binding.attachTo(session);
    }

    _attachers.add(attach);
    final current = _currentSession;
    if (current != null) {
      _activeSubs.add(attach(current, _attachGeneration));
    }
  }

  void _swapSessionIfChanged() {
    final next = session;
    if (identical(next, _currentSession)) return;
    // Bump BEFORE cancelling: any in-flight dispatch that completes after
    // this point will see a stale boundGen and drop. Cancel afterwards to
    // also stop NEW emissions from reaching us.
    _attachGeneration++;
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
    _currentSession = next;
    if (next != null) {
      for (final attach in _attachers) {
        _activeSubs.add(attach(next, _attachGeneration));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _swapSessionIfChanged();
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _swapSessionIfChanged();
  }

  @override
  void dispose() {
    // Bump so any in-flight handler sees a stale boundGen and drops out
    // before touching this State's fields.
    _attachGeneration++;
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
    _attachers.clear();
    super.dispose();
  }
}
