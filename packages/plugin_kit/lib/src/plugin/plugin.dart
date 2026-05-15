/// Internal library that consolidates the runtime/plugin/service/extensions
/// surface so they can share library-private members (notably
/// [StatefulPluginService._bindContext],
/// [StatefulPluginService._unbindContext], and the per-context subscription
/// tracking on [Plugin]).
///
/// Each `part` file below is part of this library and may use any other
/// part's private members. Files outside this library see only the public
/// API surface (re-exported via `lib/plugin_kit.dart`).
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../config_node.dart';
import '../event_bus.dart';
import '../priority.dart';
import '../service_registry.dart';
import '../settings.dart';
import '../typed_handles.dart';
import '../types.dart';
import 'exceptions.dart';

part 'core.dart';
part 'extensions.dart';
part 'runtime.dart';
part 'runtime_session.dart';
part 'service.dart';
