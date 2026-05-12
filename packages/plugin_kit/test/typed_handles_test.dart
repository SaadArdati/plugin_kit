import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('Namespace', () {
    test('exposes its underlying String via value', () {
      const ns = Namespace('agent');
      expect(ns.value, 'agent');
    });

    test('equal namespaces compare equal and hash to the same bucket', () {
      const a = Namespace('agent');
      const b = Namespace('agent');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Namespace works as a Map key keyed by its String', () {
      const a = Namespace('agent');
      final map = <Namespace, int>{a: 1};
      expect(map[const Namespace('agent')], 1);
      expect(map[const Namespace('search')], isNull);
    });

    test('child appends a sub-namespace under value with a dot separator', () {
      const a = Namespace('agent');
      final nested = a.child('system_prompt');
      expect(nested.value, 'agent.system_prompt');
      expect(nested, equals(const Namespace('agent.system_prompt')));
    });

    test('child chains arbitrarily deep', () {
      const a = Namespace('agent');
      final deep = a.child('system_prompt').child('file_tree');
      expect(deep.value, 'agent.system_prompt.file_tree');
    });

    test('service produces a ServiceId inside this namespace', () {
      const a = Namespace('agent');
      final id = a.service('model');
      expect(id.value, 'agent.model');
      expect(id, equals(const ServiceId('agent.model')));
    });

    test('call() is a shorthand for service(id)', () {
      const a = Namespace('agent');
      expect(a('model'), equals(a.service('model')));
      expect(a('model').value, 'agent.model');
    });

    test('has() matches direct children of the namespace', () {
      const a = Namespace('agent');
      expect(a.has(const ServiceId('agent.model')), isTrue);
    });

    test('has() matches nested descendants at any depth', () {
      const a = Namespace('agent');
      expect(a.has(const ServiceId('agent.system_prompt.scope')), isTrue);
    });

    test(
      'has() rejects a flat service id that happens to share the namespace name',
      () {
        const a = Namespace('agent');
        expect(a.has(const ServiceId('agent')), isFalse);
      },
    );

    test('has() rejects a different namespace that shares a prefix string', () {
      const a = Namespace('agent');
      expect(a.has(const ServiceId('agentic.model')), isFalse);
    });

    test('has() rejects unrelated service ids', () {
      const a = Namespace('agent');
      expect(a.has(const ServiceId('chat.greeter')), isFalse);
    });

    test('nested namespace.has only matches its own subtree', () {
      final agentSub = const Namespace('agent').child('sub');
      expect(agentSub.has(const ServiceId('agent.sub.foo')), isTrue);
      expect(agentSub.has(const ServiceId('agent.foo')), isFalse);
      expect(agentSub.has(const ServiceId('agent.subzero.foo')), isFalse);
    });
  });

  group('ServiceId', () {
    test('exposes its underlying String via value', () {
      const s = ServiceId('settings');
      expect(s.value, 'settings');
    });

    test('flat id reports null namespace and itself as the leaf', () {
      const s = ServiceId('settings');
      expect(s.namespace, isNull);
      expect(s.id, 'settings');
      expect(s.topNamespace, isNull);
    });

    test('namespaced constructor joins namespace and id with a dot', () {
      const ns = Namespace('agent');
      const s = ServiceId.namespaced(ns, 'model');
      expect(s.value, 'agent.model');
      expect(s.namespace, equals(const Namespace('agent')));
      expect(s.id, 'model');
      expect(s.topNamespace, equals(const Namespace('agent')));
    });

    test('namespaced constructor and Namespace.service produce equal ids', () {
      const ns = Namespace('agent');
      expect(
        const ServiceId.namespaced(ns, 'model'),
        equals(const Namespace('agent').service('model')),
      );
    });

    test('two ServiceIds with the same value are equal', () {
      const a = ServiceId.namespaced(Namespace('agent'), 'model');
      const b = ServiceId.namespaced(Namespace('agent'), 'model');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('ServiceIds with different values are unequal', () {
      const a = ServiceId.namespaced(Namespace('agent'), 'model');
      const b = ServiceId.namespaced(Namespace('agent'), 'temperature');
      expect(a, isNot(equals(b)));
    });

    test('ServiceId works as a Map key keyed by its String', () {
      const a = ServiceId.namespaced(Namespace('agent'), 'model');
      final map = <ServiceId, int>{a: 1};
      expect(map[const ServiceId.namespaced(Namespace('agent'), 'model')], 1);
      expect(
        map[const ServiceId.namespaced(Namespace('agent'), 'temperature')],
        isNull,
      );
    });

    test('namespace returns the FULL prefix (lastIndexOf semantics)', () {
      const s = ServiceId('a.b.c.d');
      expect(s.namespace, equals(const Namespace('a.b.c')));
      expect(s.id, 'd');
    });

    test('topNamespace returns the FIRST segment (indexOf semantics)', () {
      const s = ServiceId('a.b.c.d');
      expect(s.topNamespace, equals(const Namespace('a')));
    });

    test('namespace and topNamespace agree when there is exactly one dot', () {
      const s = ServiceId('agent.model');
      expect(s.namespace, equals(const Namespace('agent')));
      expect(s.topNamespace, equals(const Namespace('agent')));
      expect(s.id, 'model');
    });

    test('leading dot is treated as no namespace for both getters', () {
      const s = ServiceId('.weird');
      expect(s.namespace, isNull);
      expect(s.topNamespace, isNull);
      expect(s.id, '.weird');
    });
  });

  group('PluginId.wildcard', () {
    test('wraps the internal wildcard sentinel value', () {
      expect(PluginId.wildcard.value, '__pk_wildcard__');
    });

    test(
      'compares equal to a manually-constructed internal wildcard PluginId',
      () {
        expect(PluginId.wildcard, equals(const PluginId('__pk_wildcard__')));
      },
    );
  });

  group('PluginId.winnerScoped', () {
    test('wraps the internal winner-scoped sentinel value', () {
      expect(PluginId.winnerScoped.value, '__pk_winner__');
    });
  });

  group('Pin', () {
    test(
      'Pin(plugin, segments) joins segments with "." into the wire form',
      () {
        final pin = Pin('chat', ['agent', 'model']);
        expect(pin.pluginId, equals(const PluginId('chat')));
        expect(pin.serviceId, equals(const ServiceId('agent.model')));
        expect(pin.isWildcard, isFalse);
        expect(pin.wire, 'chat:agent.model');
      },
    );

    test('Pin(plugin, [single]) handles non-namespaced service ids', () {
      final pin = Pin('chat', ['greeter']);
      expect(pin.pluginId, equals(const PluginId('chat')));
      expect(pin.serviceId, equals(const ServiceId('greeter')));
      expect(pin.wire, 'chat:greeter');
    });

    test('Pin.wildcard(segments) reports isWildcard and serializes with *', () {
      final pin = Pin.wildcard(['agent', 'model']);
      expect(pin.isWildcard, isTrue);
      expect(pin.pluginId, equals(PluginId.wildcard));
      expect(pin.wire, '*:agent.model');
    });

    test('two Pins with the same wire compare equal', () {
      final a = Pin('chat', ['agent', 'model']);
      final b = Pin('chat', ['agent', 'model']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('Pin.fromWire round-trips plugin-scoped wire format', () {
      const pin = Pin.fromWire('chat:agent.model');
      expect(pin.pluginId, equals(const PluginId('chat')));
      expect(pin.serviceId, equals(const ServiceId('agent.model')));
      expect(pin.isWildcard, isFalse);
    });

    test('Pin.fromWire round-trips wildcard form', () {
      const pin = Pin.fromWire('*:agent.model');
      expect(pin.pluginId, equals(PluginId.wildcard));
      expect(pin.serviceId, equals(const ServiceId('agent.model')));
      expect(pin.isWildcard, isTrue);
    });

    test('Pin.fromWire preserves multi-colon servicePart after first :', () {
      const pin = Pin.fromWire('foo:bar:baz');
      expect(pin.pluginId, equals(const PluginId('foo')));
      expect(pin.serviceId, equals(const ServiceId('bar:baz')));
    });

    group('Pin.fromWire access failures throw FormatException', () {
      test('empty value', () {
        const pin = Pin.fromWire('');
        expect(() => pin.pluginId, throwsFormatException);
      });

      test('no colon', () {
        const pin = Pin.fromWire('plugin');
        expect(() => pin.pluginId, throwsFormatException);
      });

      test('leading colon (no plugin id)', () {
        const pin = Pin.fromWire(':svc');
        expect(() => pin.pluginId, throwsFormatException);
      });

      test('trailing colon (no service id)', () {
        const pin = Pin.fromWire('plugin:');
        expect(() => pin.serviceId, throwsFormatException);
      });
    });

    test('Pin works as a Map key by structural string equality', () {
      final a = Pin('chat', ['agent', 'model']);
      final map = <Pin, int>{a: 1};
      final lookup = Pin('chat', ['agent', 'model']);
      expect(map[lookup], 1);
      expect(map[Pin('chat', ['other'])], isNull);
    });

    test('Pin built from chain compares equal to Pin built from segments', () {
      final viaChain = const PluginId(
        'chat',
      ).namespace('agent').service('model');
      final viaSegments = Pin('chat', ['agent', 'model']);
      expect(viaChain, equals(viaSegments));
    });
  });

  group('PluginId.service / .namespace', () {
    test('service() pairs plugin and service id into a Pin', () {
      final key = const PluginId(
        'chat',
      ).service(const ServiceId('agent.model'));
      expect(key.wire, 'chat:agent.model');
      expect(key, equals(Pin('chat', ['agent', 'model'])));
    });

    test('PluginId.wildcard.service produces a wildcard key', () {
      final key = PluginId.wildcard.service(const ServiceId('agent.tools'));
      expect(key.isWildcard, isTrue);
      expect(key.wire, '*:agent.tools');
    });

    test('namespace().service() chains plugin, namespace, and leaf', () {
      final key = const PluginId('chat').namespace('agent').service('model');
      expect(key.wire, 'chat:agent.model');
    });

    test('namespace() shorthand call() is equivalent to .service()', () {
      final viaCall = const PluginId('chat').namespace('agent')('model');
      final viaService = const PluginId(
        'chat',
      ).namespace('agent').service('model');
      expect(viaCall, equals(viaService));
    });

    test('namespace().child() deepens the namespace before .service()', () {
      final key = const PluginId(
        'chat',
      ).namespace('agent').child('system_prompt').service('scope');
      expect(key.wire, 'chat:agent.system_prompt.scope');
    });

    test('service() accepts a bare String dotted path', () {
      final key = const PluginId('chat').service('agent.model');
      expect(key.wire, 'chat:agent.model');
      expect(key, equals(Pin('chat', ['agent', 'model'])));
    });

    test('service() accepts a deeper bare String dotted path', () {
      final key = const PluginId('chat').service('agent.system_prompt.scope');
      expect(key.wire, 'chat:agent.system_prompt.scope');
    });

    test('service() with a non-namespaced bare String works', () {
      final key = const PluginId('chat').service('greeter');
      expect(key.wire, 'chat:greeter');
    });

    test(
      'service() with a bare String and with a ServiceId produce equal Pins',
      () {
        final viaString = const PluginId('chat').service('agent.model');
        final viaTyped = const PluginId(
          'chat',
        ).service(const ServiceId('agent.model'));
        expect(viaString, equals(viaTyped));
      },
    );

    test('PluginId.wildcard.service accepts a bare String', () {
      final key = PluginId.wildcard.service('agent.tools');
      expect(key.isWildcard, isTrue);
      expect(key.wire, '*:agent.tools');
    });
  });

  group('implements String', () {
    String acceptString(String s) => s;

    test('ServiceId flows into a String parameter without conversion', () {
      const id = ServiceId('telemetry.redactor');
      expect(acceptString(id), 'telemetry.redactor');
    });

    test('PluginId flows into a String parameter without conversion', () {
      const p = PluginId('chat');
      expect(acceptString(p), 'chat');
    });

    test('Namespace flows into a String parameter without conversion', () {
      const ns = Namespace('agent');
      expect(acceptString(ns), 'agent');
    });

    test('Pin flows into a String parameter without conversion', () {
      final pin = Pin('chat', ['agent', 'model']);
      expect(acceptString(pin), 'chat:agent.model');
    });

    test('typed identifier interpolates as its underlying String', () {
      const id = ServiceId('telemetry.redactor');
      expect('$id', 'telemetry.redactor');
    });

    test('typed identifier compares == to the matching String literal', () {
      const id = ServiceId('telemetry.redactor');
      expect(id == 'telemetry.redactor', isTrue);
    });

    test('typed identifier looks up in a Map<String, T>', () {
      const id = ServiceId('telemetry.redactor');
      final map = <String, int>{'telemetry.redactor': 7};
      expect(map[id], 7);
    });

    // Documentation, not an executable test: the reverse direction must
    // remain a compile error. Uncommenting either line below should yield
    // `argument_type_not_assignable` from the analyzer.
    //
    // void requireServiceId(ServiceId id) {}
    // requireServiceId('telemetry.redactor');
  });
}
