// Unit tests (no database, except the tagged test at the end) for the IoC
// Container (lib/src/container) and the capsule Manager (lib/src/capsule).

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:test/test.dart';

class _Service {
  _Service(this.name);
  final String name;
}

void main() {
  group('Container', () {
    late Container c;
    setUp(() => c = Container());

    test('bind and make call the factory with 0, 1 or 2 arguments', () {
      c.bind('zero', () => 'z');
      c.bind('one', (Container container) => identical(container, c));
      c.bind('two', (Container container, dynamic parameters) => parameters);
      expect(c.make('zero'), 'z');
      expect(c.make('one'), isTrue);
      expect(c.make('two', ['p']), ['p']);
    });

    test('bind creates a new object each time, singleton one', () {
      c.bind('svc', () => _Service('a'));
      expect(identical(c.make('svc'), c.make('svc')), isFalse);
      c.singleton('shared', () => _Service('b'));
      expect(identical(c.make('shared'), c.make('shared')), isTrue);
      expect(c.isShared('shared'), isTrue);
      expect(c.isShared('svc'), isFalse);
      expect(c.isShared('unknown'), isFalse);
    });

    test('bindIf keeps the first binding', () {
      c.bind('svc', () => 'first');
      c.bindIf('svc', () => 'second');
      c.bindIf('other', () => 'other');
      expect(c.make('svc'), 'first');
      expect(c.make('other'), 'other');
    });

    test('instance, bound and resolved', () {
      expect(c.bound('cfg'), isFalse);
      c.instance('cfg', {'a': 1});
      expect(c.bound('cfg'), isTrue);
      expect(c.resolved('cfg'), isTrue);
      expect(c.make('cfg'), {'a': 1});

      c.bind('lazy', () => 1);
      expect(c.resolved('lazy'), isFalse);
      c.make('lazy');
      expect(c.resolved('lazy'), isTrue);
    });

    test('an empty list, empty map or null instance is still bound', () {
      c.instance('list', []);
      c.instance('map', {});
      c.instance('none', null);
      expect(c.bound('list'), isTrue);
      expect(c.make('list'), []);
      expect(c.make('map'), {});
      expect(c.bound('none'), isTrue);
      expect(c.make('none'), isNull);
    });

    test('a leading backslash is ignored', () {
      c.bind(r'\App\Service', () => 's');
      expect(c.bound(r'\App\Service'), isTrue);
      expect(c.bound(r'App\Service'), isTrue);
      expect(c.make(r'\App\Service'), 's');
    });

    test('make of an unknown type throws BindingResolutionException', () {
      expect(
          () => c.make('nothing'), throwsA(isA<BindingResolutionException>()));
      c.bind('self'); // no factory: nothing to build without reflection
      expect(() => c.make('self'), throwsA(isA<BindingResolutionException>()));
    });

    test('a string concrete resolves another binding', () {
      c.singleton('impl', () => _Service('impl'));
      c.bind('contract', 'impl');
      expect((c.make('contract') as _Service).name, 'impl');
      expect(identical(c.make('contract'), c.make('impl')), isTrue);
    });

    test('alias, alias chains and bind with an alias map', () {
      c.instance('db', 'database');
      c.alias('db', 'database.manager');
      c.alias('database.manager', 'dbm');
      expect(c.isAlias('dbm'), isTrue);
      expect(c.make('dbm'), 'database');
      expect(c.bound('dbm'), isTrue);

      c.bind({'events': 'dispatcher'}, () => 'events!');
      expect(c.make('dispatcher'), 'events!');
      expect(c.getAlias('dispatcher'), 'events');
    });

    test('extend decorates future and existing instances', () {
      c.bind('svc', () => 'a');
      c.extend('svc', (value, Container container) => '$value+b');
      c.extend('svc', (value) => '$value+c');
      expect(c.make('svc'), 'a+b+c');

      c.instance('cfg', 1);
      c.extend('cfg', (value) => value + 1);
      expect(c.make('cfg'), 2);
    });

    test('rebinding callbacks run when the binding changes', () {
      final seen = [];
      c.bind('svc', () => 'v1');
      expect(c.rebinding('svc', (Container _, value) => seen.add(value)), 'v1');
      c.make('svc');
      c.bind('svc', () => 'v2');
      c.instance('svc', 'v3');
      expect(seen, ['v2', 'v3']);
    });

    test('refresh and Class@method callbacks need reflection', () {
      expect(() => c.refresh('svc', Object(), 'setSvc'),
          throwsA(isA<UnsupportedError>()));
      expect(() => c.call('Service@handle'), throwsA(isA<UnsupportedError>()));
      expect(() => c.call(() => 1, [], 'handle'),
          throwsA(isA<UnsupportedError>()));
    });

    test('tag and tagged', () {
      c.bind('a', () => 1);
      c.bind('b', () => 2);
      c.tag(['a', 'b'], ['numbers']);
      expect(c.tagged('numbers'), [1, 2]);
      expect(c.tagged('none'), []);
    });

    test('share caches each closure separately', () {
      var calls = 0;
      final first = c.share((Container _) => _Service('${++calls}'));
      final second = c.share((Container _) => _Service('other'));
      c.bind('first', first);
      c.bind('second', second);
      expect((c.make('first') as _Service).name, '1');
      expect((c.make('first') as _Service).name, '1');
      expect((c.make('second') as _Service).name, 'other');
      expect(calls, 1);
    });

    test('contextual binding: when(...).needs(...).give(...)', () {
      c.bind('logger', () => 'file logger');
      c.bind('memory', () => 'memory logger');
      c.bind('report', (Container c) => 'report with ${c.make('logger')}');
      c.bind('job', (Container c) => 'job with ${c.make('logger')}');
      c.when('report').needs('logger').give('memory');
      c.when('job').needs('logger').give((Container _) => 'closure logger');
      expect(c.make('report'), 'report with memory logger');
      expect(c.make('job'), 'job with closure logger');
      expect(c.make('logger'), 'file logger');
    });

    test('resolving and afterResolving callbacks', () {
      final events = <String>[];
      c.bind('svc', () => _Service('s'));
      c.bind('other', () => _Service('o'));
      c.resolving((Object? o) => events.add('global ${(o as _Service).name}'));
      c.resolving('svc', (_Service s, Container _) => events.add('svc'));
      c.afterResolving('svc', (_Service s) => events.add('after svc'));
      c.afterResolving((Object? o) => events.add('after global'));
      c.make('svc');
      c.make('other');
      expect(events, [
        'global s',
        'svc',
        'after global',
        'after svc',
        'global o',
        'after global',
      ]);
    });

    test('call and wrap pass the parameters to the callback', () {
      expect(c.call((int a, int b) => a + b, [2, 3]), 5);
      expect(c.call(() => 'no args'), 'no args');
      final wrapped = c.wrap((String s) => s.toUpperCase(), ['x']);
      expect(wrapped(), 'X');
    });

    test('[] and []= (ArrayAccess)', () {
      c['value'] = 42;
      c['factory'] = () => _Service('f');
      expect(c['value'], 42);
      expect((c['factory'] as _Service).name, 'f');
      expect(c.offsetExists('value'), isTrue);
      c.offsetUnset('value');
      expect(c.offsetExists('value'), isFalse);
    });

    test('forgetInstance, forgetInstances and flush', () {
      c.instance('a', 1);
      c.instance('b', 2);
      c.forgetInstance('a');
      expect(c.bound('a'), isFalse);
      c.forgetInstances();
      expect(c.bound('b'), isFalse);
      c.bind('x', () => 1);
      c.alias('x', 'y');
      c.flush();
      expect(c.bound('x'), isFalse);
      expect(c.isAlias('y'), isFalse);
    });

    test('setInstance / getInstance', () {
      final previous = Container.instanceProp;
      try {
        c.setInstance(c);
        expect(identical(Container().getInstance(), c), isTrue);
      } finally {
        Container.instanceProp = previous;
      }
    });
  });

  group('Manager (capsule)', () {
    test('default configuration and addConnection', () {
      final manager = Manager()
        ..addConnection({'driver': 'pgsql', 'database': 'a'})
        ..addConnection({'driver': 'mysql', 'database': 'b'}, 'other');
      final config = manager.getContainer()!['config'];
      expect(config, isA<Fluent>());
      expect(config['database.default'], 'default');
      final connections = config['database.connections'] as Map;
      expect(connections.keys, ['default', 'other']);
      expect(connections['other']['driver'], 'mysql');
      expect(manager.getDatabaseManager().getDefaultConnection(), 'default');
    });

    test('a given container keeps its config', () {
      final container = Container()..instance('config', Fluent());
      final manager = Manager(container);
      expect(identical(manager.getContainer(), container), isTrue);
      expect(container['config']['database.default'], 'default');
    });

    test('the event dispatcher', () {
      final manager = Manager();
      expect(manager.getEventDispatcher(), isNull);
      final dispatcher = Object();
      manager.setEventDispatcher(dispatcher);
      expect(manager.getEventDispatcher(), same(dispatcher));
    });

    test('setAsGlobal', () {
      final previous = Manager.instance;
      try {
        final manager = Manager()..setAsGlobal();
        expect(Manager.instance, same(manager));
      } finally {
        Manager.instance = previous;
      }
    });

    test('connection(), table() and schema() use this manager, not the global',
        () async {
      final previous = Manager.instance;
      Manager.instance = null;
      try {
        final manager = Manager()
          ..addConnection({
            'driver': 'pgsql',
            'host': 'localhost',
            'port': '5432',
            'database': 'banco_teste',
            'username': 'dart',
            'password': 'dart',
            'schema': ['public'],
          });
        final db = await manager.connection();
        expect(await db.select('select 1 as one'), [
          {'one': 1}
        ]);
        expect((await manager.table('pg_class')).fromProp, 'pg_class');
        expect(await manager.schema(), isA<SchemaBuilder>());
        await manager.getDatabaseManager().purge();
      } finally {
        Manager.instance = previous;
      }
    }, tags: ['integration']);
  });
}
