// Unit tests (no database) for the PHP-helper ports: Utils
// (lib/src/utils/utils.dart), Str.parseCallback, Fluent and Arr. Each group
// covers a behaviour that used to differ from the PHP/Laravel namesake.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/support/arr.dart';
import 'package:eloquent/src/support/str.dart';
import 'package:test/test.dart';

void main() {
  group('Utils.explode with a limit (PHP semantics)', () {
    test('a positive limit keeps the rest in the last piece', () {
      expect(Utils.explode('.', 'a.b.c', 2), equals(['a', 'b.c']));
      expect(Utils.explode('::', 'pgsql::read', 2), equals(['pgsql', 'read']));
      expect(Utils.explode('.', 'a.b.c', 3), equals(['a', 'b', 'c']));
      expect(Utils.explode('.', 'a.b.c', 10), equals(['a', 'b', 'c']));
    });

    test('a limit of 0 behaves as 1', () {
      expect(Utils.explode('.', 'a.b.c', 0), equals(['a.b.c']));
      expect(Utils.explode('.', 'a.b.c', 1), equals(['a.b.c']));
    });

    test('a negative limit drops that many pieces from the end', () {
      expect(Utils.explode('.', 'a.b.c', -1), equals(['a', 'b']));
      expect(Utils.explode('.', 'a.b.c', -3), isEmpty);
      expect(Utils.explode('.', 'a.b.c', -5), isEmpty);
    });

    test('a RegExp separator keeps the rest as written', () {
      expect(Utils.explode(RegExp(r'\s+'), 'a  b   c d', 2),
          equals(['a', 'b   c d']));
    });
  });

  group('Utils.array_get (dot notation, as Arr::get)', () {
    final config = {
      'pgsql': {'host': 'localhost', 'port': 5432},
      'with.dot': 'literal',
      'with': {'dot': 'nested'},
      'list': [
        {'id': 1},
        {'id': 2},
      ],
    };

    test('reads nested keys', () {
      expect(Utils.array_get(config, 'pgsql.host'), equals('localhost'));
      expect(Utils.array_get(config, 'list.1.id'), equals(2));
    });

    test('a top-level key with a dot wins over the path', () {
      expect(Utils.array_get(config, 'with.dot'), equals('literal'));
    });

    test('a missing path gives the default', () {
      expect(Utils.array_get(config, 'pgsql.user'), isNull);
      expect(Utils.array_get(config, 'pgsql.port.x', 'd'), equals('d'));
      expect(Utils.array_get(config, 'nope.x', () => 'lazy'), equals('lazy'));
    });
  });

  group('Utils.array_exists / data_get with a List and a String key', () {
    test('array_exists accepts numeric strings for a List', () {
      expect(Utils.array_exists([10, 20], '1'), isTrue);
      expect(Utils.array_exists([10, 20], '2'), isFalse);
      expect(Utils.array_exists([10, 20], 'x'), isFalse);
      expect(Utils.array_exists([10, 20], -1), isFalse);
    });

    test('data_get descends into lists', () {
      final target = {
        'items': [
          {'name': 'a'},
          {'name': 'b'},
        ],
      };
      expect(Utils.data_get(target, 'items.0.name'), equals('a'));
      expect(Utils.data_get(target, 'items.1'), equals({'name': 'b'}));
      expect(Utils.data_get(target, 'items.5.name', 'none'), equals('none'));
      expect(Utils.data_get(target, 'items.x', 'none'), equals('none'));
    });

    test('data_get with * plucks from a List or a Map', () {
      final list = [
        {'n': 'a'},
        {'n': 'b'},
      ];
      expect(Utils.data_get(list, '*.n'), equals(['a', 'b']));
      final map = {
        'u1': {'n': 'a'},
        'u2': {'n': 'b'},
      };
      expect(Utils.data_get(map, '*.n'), equals(['a', 'b']));
      expect(Utils.data_get('scalar', '*.n', 'd'), equals('d'));
    });

    test('data_get with two * collapses the result', () {
      final target = [
        {
          'tags': [
            {'t': 'x'},
            {'t': 'y'},
          ]
        },
        {
          'tags': [
            {'t': 'z'},
          ]
        },
      ];
      expect(Utils.data_get(target, '*.tags.*.t'), equals(['x', 'y', 'z']));
    });
  });

  group('Utils.array_collapse', () {
    test('a List of lists', () {
      expect(
          Utils.array_collapse([
            [1, 2],
            'skipped',
            [3],
          ]),
          equals([1, 2, 3]));
    });

    test('a Map of lists', () {
      expect(
          Utils.array_collapse({
            'x': [1, 2],
            'y': [3],
          }),
          equals([1, 2, 3]));
    });

    test('a List of maps merges them', () {
      expect(
          Utils.array_collapse([
            {'a': 1, 'b': 1},
            {'b': 2},
          ]),
          equals({'a': 1, 'b': 2}));
    });
  });

  group('Utils.array_shift / array_pop', () {
    test('array_shift on a Map returns the value', () {
      final map = {'a': 1, 'b': 2};
      expect(Utils.array_shift(map), equals(1));
      expect(map, equals({'b': 2}));
      expect(Utils.array_shift(<String, int>{}), isNull);
    });

    test('array_shift on a List', () {
      final list = [1, 2];
      expect(Utils.array_shift(list), equals(1));
      expect(list, equals([2]));
      expect(Utils.array_shift([]), isNull);
    });

    test('array_pop returns the removed value, null when empty', () {
      // Called through a Function so the test compiles whatever the return
      // type is.
      final Function pop = Utils.array_pop;
      final list = [1, 2];
      expect(pop(list), equals(2));
      expect(list, equals([1]));
      final map = {'a': 1, 'b': 2};
      expect(pop(map), equals(2));
      expect(map, equals({'a': 1}));
      expect(pop([]), isNull);
      expect(pop(<String, int>{}), isNull);
    });
  });

  group('Utils.map_except_sd', () {
    test('removes a key whose value is a map', () {
      final config = <String, dynamic>{
        'driver': 'pgsql',
        'read': {'host': 'r'},
        'write': {'host': 'w'},
      };
      final result = Utils.map_except_sd(config, ['read', 'write']);
      expect(result, equals({'driver': 'pgsql'}));
      // It works in place, as documented.
      expect(identical(result, config), isTrue);
    });

    test('still removes the keys inside nested maps (documented example)', () {
      final map = <String, dynamic>{
        'driver': 'mysql',
        'host': '127.0.0.1',
        'level1': <String, dynamic>{
          'read': true,
          'write': false,
          'level2': <String, dynamic>{'banana': 'good'},
        },
      };
      expect(
          Utils.map_except_sd(map, ['read', 'write']),
          equals({
            'driver': 'mysql',
            'host': '127.0.0.1',
            'level1': {
              'level2': {'banana': 'good'}
            },
          }));
      expect(Utils.map_except_sd(map, 'host'), isNot(contains('host')));
      expect(() => Utils.map_except_sd(map, 1), throwsException);
    });

    test('ConnectionFactory read/write configs drop read and write', () {
      final factory = ConnectionFactory(Container());
      final config = <String, dynamic>{
        'driver': 'pgsql',
        'host': 'main',
        'read': <String, dynamic>{
          'host': ['r1', 'r2'],
        },
        'write': <String, dynamic>{'host': 'w'},
      };
      final write = factory.getWriteConfig(config);
      expect(write['host'], equals('w'));
      expect(write.containsKey('read'), isFalse);
      expect(write.containsKey('write'), isFalse);

      final read = factory.getReadConfig(config);
      expect(read['host'], isIn(['r1', 'r2']));
      expect(read.containsKey('read'), isFalse);
      expect(read.containsKey('write'), isFalse);
    });
  });

  group('Utils.ltrim', () {
    test('the default list is PHP\'s', () {
      expect(Utils.ltrim(' \n\r\t\v\x00x '), equals('x '));
      expect(Utils.ltrim('\u00a0x'), equals('\u00a0x'));
      expect(Utils.ltrim(' \v\x00x ', null), equals('x '));
    });

    test('chars are literal, not a regular expression class', () {
      expect(Utils.ltrim(']]a]', ']'), equals('a]'));
      expect(Utils.ltrim('--a-', '-'), equals('a-'));
      expect(Utils.ltrim('a-b', 'a-c'), equals('b'));
      expect(Utils.ltrim('^^a', '^'), equals('a'));
      expect(Utils.ltrim('\\Foo\\Bar', '\\'), equals('Foo\\Bar'));
      // Container.normalize passes two backslashes.
      expect(Utils.ltrim('\\\\Foo', '\\\\'), equals('Foo'));
      expect(Utils.ltrim('xxy', ''), equals('xxy'));
    });
  });

  group('Utils.substr (PHP 8 semantics)', () {
    test('a negative length leaves characters out at the end', () {
      expect(Utils.substr('abcdef', 1, -1), equals('bcde'));
      expect(Utils.substr('abcdef', -3, -1), equals('de'));
      expect(Utils.substr('abcdef', 0, -10), equals(''));
      expect(Utils.substr('abcdef', 4, -3), equals(''));
    });

    test('an offset past the end gives an empty string', () {
      expect(Utils.substr('abc', 3), equals(''));
      expect(Utils.substr('abc', 10), equals(''));
      expect(Utils.substr('abc', 10, 2), equals(''));
    });

    test('the usual cases', () {
      expect(Utils.substr('abcdef', 1, 3), equals('bcd'));
      expect(Utils.substr('abcdef', -2, 10), equals('ef'));
      expect(Utils.substr('abc', -10, 2), equals('ab'));
      expect(Utils.substr('abc', -10), equals('abc'));
      expect(Utils.substr('abc', 1, 0), equals(''));
    });
  });

  group('array_pluck without a key value', () {
    final rows = [
      {'id': 1, 'name': 'a'},
      {'name': 'b'},
      {'id': null, 'name': 'c'},
    ];

    test('Utils.array_pluck keys the item by null', () {
      expect(
          Utils.array_pluck(rows, 'name', 'id'), equals({1: 'a', null: 'c'}));
    });

    test('Arr.pluck keys the item by null', () {
      expect(Arr.pluck(rows, 'name', 'id'), equals({1: 'a', null: 'c'}));
    });
  });

  group('Arr.dataGet with a List', () {
    final rows = [
      {'id': 1, 'name': 'John'},
      {'id': 2, 'name': 'Jane'},
    ];

    test('a path of segments may hold int indexes', () {
      expect(Arr.dataGet({'rows': rows}, ['rows', 1, 'id']), equals(2));
      expect(Arr.dataGet(rows, [5, 'id']), isNull);
      // A String index is not a List index for Arr (see arr_test.dart).
      expect(Arr.dataGet({'rows': rows}, 'rows.1.id'), isNull);
    });
  });

  group('Str.parseCallback', () {
    test('splits at the first @', () {
      expect(Str.parseCallback('a@b@c', null), equals(['a', 'b@c']));
      expect(Str.parseCallback('Class@method', 'handle'),
          equals(['Class', 'method']));
      expect(Str.parseCallback('Class', 'handle'), equals(['Class', 'handle']));
      expect(Str.parseCallback('Class', null), equals(['Class']));
    });
  });

  group('Fluent', () {
    test('copies the given attributes', () {
      final source = <String, dynamic>{'a': 1};
      final fluent = Fluent(source);
      source['b'] = 2;
      expect(fluent.getAttributes(), equals({'a': 1}));
      expect(Fluent().getAttributes(), isEmpty);
    });

    test('get, [] and defaults', () {
      final fluent = Fluent({'a': 1, 'n': null});
      expect(fluent.get('a'), equals(1));
      expect(fluent['a'], equals(1));
      expect(fluent['missing'], isNull);
      expect(fluent.get('missing', 'd'), equals('d'));
      expect(fluent.get('missing', () => 'lazy'), equals('lazy'));
      // A key set to null is returned as null, not as the default.
      expect(fluent.get('n', 'd'), isNull);
    });

    test('set, []= and unset', () {
      final fluent = Fluent();
      fluent['a'] = 1;
      fluent.set('b', 2);
      fluent.offsetSet('c', 3);
      expect(fluent.toJson(), equals('{"a":1,"b":2,"c":3}'));
      fluent.unset('a');
      fluent.offsetUnset('b');
      expect(fluent.attributes, equals({'c': 3}));
    });

    test('isset / offsetExists are false for null values (PHP isset)', () {
      final fluent = Fluent({'a': 1, 'n': null});
      expect(fluent.isset('a'), isTrue);
      expect(fluent.offsetExists('a'), isTrue);
      expect(fluent.isset('missing'), isFalse);
      expect(fluent.isset('n'), isFalse);
      expect(fluent.offsetExists('n'), isFalse);
    });
  });

  group('other Utils helpers versus PHP', () {
    test('array_rand with one key returns the key, not a list', () {
      final list = ['a', 'b', 'c'];
      for (var i = 0; i < 20; i++) {
        final key = Utils.array_rand(list);
        expect(key, isA<int>());
        expect(key, inInclusiveRange(0, 2));
      }
    });

    test('array_rand with several keys returns distinct keys in order', () {
      final list = ['a', 'b', 'c', 'd'];
      for (var i = 0; i < 20; i++) {
        final keys = Utils.array_rand(list, 3) as List;
        expect(keys.length, equals(3));
        expect(keys.toSet().length, equals(3));
        expect(keys, equals([...keys]..sort()));
      }
      expect(Utils.array_rand(list, 4), equals([0, 1, 2, 3]));
      expect(() => Utils.array_rand(list, 5), throwsArgumentError);
      expect(() => Utils.array_rand([], 1), throwsArgumentError);
    });

    test('empty is true for PHP\'s empty values', () {
      for (final v in ['', null, 0, 0.0, false, '0', [], {}]) {
        expect(Utils.empty(v), isTrue, reason: 'empty($v)');
      }
      for (final v in [
        ' ',
        1,
        true,
        '00',
        'a',
        [0],
        {'a': null}
      ]) {
        expect(Utils.empty(v), isFalse, reason: 'empty($v)');
      }
    });

    test('endsWith never matches an empty needle', () {
      expect(Utils.endsWith('abc', 'bc'), isTrue);
      expect(Utils.endsWith('abc', ''), isFalse);
      expect(Utils.endsWith('abc', ['']), isFalse);
      expect(Utils.endsWith('x::read', ['::read', '::write']), isTrue);
      expect(Utils.endsWith('ab', ['xab']), isFalse);
    });

    test('strval of null and bools', () {
      expect(Utils.strval(null), equals(''));
      expect(Utils.strval(true), equals('1'));
      expect(Utils.strval(false), equals(''));
      expect(Utils.strval(12), equals('12'));
    });

    test('map_first_key of an empty map is null', () {
      expect(Utils.map_first_key({}), isNull);
      expect(Utils.map_first_key({'a': 1}), equals('a'));
    });

    test('map_add_sd also sets a key whose value is null (Arr::add)', () {
      final map = <String, dynamic>{'prefix': null, 'name': 'x'};
      Utils.map_add_sd(map, 'prefix', '');
      Utils.map_add_sd(map, 'name', 'y');
      Utils.map_add_sd(map, 'other', 1);
      expect(map, equals({'prefix': '', 'name': 'x', 'other': 1}));
    });
  });
}
