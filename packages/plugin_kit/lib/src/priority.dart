library;

/// Preset priority stops and relative helpers for plugin_kit's priority-based
/// systems.
///
/// Both the [ServiceRegistry] and the [EventBus] use the same polarity:
/// higher wins / higher runs first. Service resolution returns the
/// highest-priority registration; event dispatch invokes the highest-priority
/// handler first (and that handler can mutate or stop the cascade
/// for the rest).
///
/// Values are plain [int]s; the parameter type on `registerSingleton`,
/// `on`, and similar APIs stays `int`. Use [Priority] when you want a
/// discoverable, mnemonic stop. Use raw integers when you have a domain
/// reason to.
///
/// ```dart
/// // Most code: pick a band.
/// registry.registerSingleton<Router>(id, () => MyRouter());
/// registry.registerSingleton<Router>(
///   id, () => EnterpriseRouter(),
///   priority: Priority.elevated,
/// );
///
/// // "I want to beat whatever they registered, with headroom above me."
/// registry.registerSingleton<Router>(
///   id, () => CompliancePlugin(),
///   priority: Priority.above(Priority.elevated, by: 100),
/// );
/// ```
///
/// Band layout (widening gaps so [system] is genuinely out of the way):
///
/// | Stop       | Value  | Intended use                                  |
/// |------------|-------:|-----------------------------------------------|
/// | [lowest]   |      0 | Fallback-only; loses every contest.           |
/// | [low]      |    100 | Barely-there defaults, seed implementations.  |
/// | [normal]   |    500 | Default for everything; mid-stack.            |
/// | [elevated] |   1000 | Conventional "I'm an override" stop.          |
/// | [high]     |   5000 | Enterprise / customer-driven override band.   |
/// | [system]   |  10000 | System-reserved; avoid in plugin code.        |
abstract final class Priority {
  const Priority._();

  /// Loses every contest. Reserve for explicit fallback-only registrations.
  static const int lowest = 0;

  /// One band above [lowest]. Barely-there defaults and seed implementations.
  static const int low = 100;

  /// Default for everything. Library-registered services, most plugin
  /// handlers. Sits mid-stack with room above and below.
  static const int normal = 500;

  /// One band above [normal]. The conventional "I'm an override" stop.
  /// First-line winner over [normal] without claiming the [high] / [system]
  /// bands.
  static const int elevated = 1000;

  /// Enterprise / customer override band. Wins over plugin-internal
  /// [elevated] overrides while still leaving room for [system].
  static const int high = 5000;

  /// System-reserved band. Avoid in plugin code unless the registration
  /// genuinely needs to outrank every other band.
  static const int system = 10000;

  /// Returns `other + by`. Use to register one (or [by]) above an existing
  /// stop, leaving the natural band's headroom intact for further overrides.
  ///
  /// ```dart
  /// Priority.above(Priority.elevated)          // 1001
  /// Priority.above(Priority.elevated, by: 50)  // 1050
  /// ```
  static int above(int other, {int by = 1}) => other + by;

  /// Returns `other - by`. Mirror of [above].
  ///
  /// ```dart
  /// Priority.below(Priority.normal)         // 499
  /// Priority.below(Priority.normal, by: 10) // 490
  /// ```
  static int below(int other, {int by = 1}) => other - by;
}
