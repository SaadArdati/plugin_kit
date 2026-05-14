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

  final List<EventBinding> _bindings = [];
  final List<EventSubscription> _activeSubs = [];
  PluginSession? _currentSession;

  /// Subscribe to events of type [E] on the current session. The
  /// subscription is re-attached automatically across session swaps and
  /// cancelled in [dispose].
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
    _addBinding(
      EventBinding.on<E>(
        (envelope) {
          if (!mounted) return;
          handler(envelope);
        },
        priority: priority,
        identifier: identifier,
      ),
    );
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
    _addBinding(
      EventBinding.on<E>((envelope) {
        if (!mounted) return;
        if (when != null && !when(envelope)) return;
        setState(() {});
      }),
    );
  }

  void _addBinding(EventBinding binding) {
    _bindings.add(binding);
    final current = _currentSession;
    if (current != null) {
      _activeSubs.add(binding.attachTo(current));
    }
  }

  void _swapSessionIfChanged() {
    final next = session;
    if (identical(next, _currentSession)) return;
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
    _currentSession = next;
    if (next != null) {
      for (final binding in _bindings) {
        _activeSubs.add(binding.attachTo(next));
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
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
    _bindings.clear();
    super.dispose();
  }
}
