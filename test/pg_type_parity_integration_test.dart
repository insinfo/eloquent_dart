// The four PostgreSQL adapters return the same Dart types and values for
// every PostgreSQL type (`pg_types: 'uniform'`, the default). A driver that
// changes a decoder in a new version breaks this test before eloquent ships
// with it. Also checks `pg_types: 'driver'` and `driver_options`.
//
// Requires localhost:5432, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _drivers = ['postgres', 'postgres_v3', 'dargres', 'dpgsql'];

Map<String, dynamic> _config(String driver,
        {String? pgTypes, Map<String, dynamic>? driverOptions}) =>
    {
      'driver': 'pgsql',
      'driver_implementation': driver,
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'schema': ['public'],
      'timezone': 'America/Sao_Paulo',
      if (pgTypes != null) 'pg_types': pgTypes,
      if (driverOptions != null) 'driver_options': driverOptions,
    };

/// A PostgreSQL expression, the Dart type it must come back as, and its
/// value.
class _Case {
  const _Case(this.name, this.sql, this.type, this.value);
  final String name;
  final String sql;
  final TypeMatcher<Object> type;
  final Object? value;
}

final _cases = <_Case>[
  // Natural Dart types.
  _Case('int2', '1::int2', isA<int>(), 1),
  _Case('int4', '(-2147483648)::int4', isA<int>(), -2147483648),
  _Case('int8', '9007199254740993::int8', isA<int>(), 9007199254740993),
  _Case('oid', '1::oid', isA<int>(), 1),
  _Case('float4', '1.1::float4', isA<double>(), 1.100000023841858),
  _Case('float8', '0.1::float8', isA<double>(), 0.1),
  _Case('bool', 'true', isA<bool>(), true),
  _Case('text', "'ção 日本'::text", isA<String>(), 'ção 日本'),
  _Case('char', "'ab'::char(4)", isA<String>(), 'ab  '),
  _Case('varchar', "'x'::varchar(3)", isA<String>(), 'x'),
  _Case('xml', "'<a/>'::xml", isA<String>(), '<a/>'),
  _Case('uuid', "'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid", isA<String>(),
      'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'),
  _Case('bytea', "decode('0102ff', 'hex')", isA<Uint8List>(), [1, 2, 255]),
  _Case('json', """'{"a":1}'::json""", isA<Map>(), {'a': 1}),
  _Case('jsonb', """'[1,"x"]'::jsonb""", isA<List>(), [1, 'x']),
  _Case(
      'date', "'2024-03-10'::date", isA<DateTime>(), DateTime.utc(2024, 3, 10)),
  _Case('timestamp', "'2024-03-10 12:34:56.789'::timestamp", isA<DateTime>(),
      DateTime.utc(2024, 3, 10, 12, 34, 56, 789)),
  _Case('timestamptz', "'2024-03-10 12:34:56.789+00'::timestamptz",
      isA<DateTime>(), DateTime.utc(2024, 3, 10, 12, 34, 56, 789)),
  // numeric: the exact text.
  _Case('numeric', '150.50::numeric(10,2)', isA<String>(), '150.50'),
  _Case('numeric big', '12345678901234567890.123456789::numeric', isA<String>(),
      '12345678901234567890.123456789'),
  // Arrays of natural types: List<T?>.
  _Case('int4[]', "'{1,NULL,3}'::int4[]", isA<List<int?>>(), [1, null, 3]),
  _Case('text[]', "'{a,NULL}'::text[]", isA<List<String?>>(), ['a', null]),
  _Case('numeric[]', "'{1.10,2}'::numeric[]", isA<List<String?>>(),
      ['1.10', '2']),
  _Case('date[]', "'{2024-01-01}'::date[]", isA<List<DateTime?>>(),
      [DateTime.utc(2024)]),
  // No natural Dart type: the server's text.
  _Case('time', "'10:20:30.5'::time", isA<String>(), '10:20:30.5'),
  _Case('timetz', "'10:20:30+03'::timetz", isA<String>(), '10:20:30+03'),
  _Case('interval', "'1 day 02:03:04'::interval", isA<String>(),
      '1 day 02:03:04'),
  _Case('interval months', "'1 year 2 mons'::interval", isA<String>(),
      '1 year 2 mons'),
  _Case('interval negative', "'-1 days +02:00:00'::interval", isA<String>(),
      '-1 days +02:00:00'),
  _Case('inet', "'10.0.0.1'::inet", isA<String>(), '10.0.0.1'),
  _Case('inet6', "'2001:db8::1/64'::inet", isA<String>(), '2001:db8::1/64'),
  _Case('cidr', "'10.0.0.0/8'::cidr", isA<String>(), '10.0.0.0/8'),
  _Case('macaddr', "'08:00:2b:01:02:03'::macaddr", isA<String>(),
      '08:00:2b:01:02:03'),
  _Case('money', '12.34::numeric::money', isA<String>(), '12.34'),
  _Case('point', "'(1,2)'::point", isA<String>(), '(1,2)'),
  _Case('line', "'{1,2,3}'::line", isA<String>(), '{1,2,3}'),
  _Case('lseg', "'[(1,2),(3,4)]'::lseg", isA<String>(), '[(1,2),(3,4)]'),
  _Case('box', "'(3,4),(1,2)'::box", isA<String>(), '(3,4),(1,2)'),
  _Case('path', "'[(1,2),(3,4)]'::path", isA<String>(), '[(1,2),(3,4)]'),
  _Case('polygon', "'((0,0),(1,0),(1,1))'::polygon", isA<String>(),
      '((0,0),(1,0),(1,1))'),
  _Case('circle', "'<(1,2),3>'::circle", isA<String>(), '<(1,2),3>'),
  _Case('bit', "B'101'", isA<String>(), '101'),
  _Case('varbit', "B'10'::varbit", isA<String>(), '10'),
  _Case('tsvector', "'a b'::tsvector", isA<String>(), "'a' 'b'"),
  _Case('int4range', "'[1,5)'::int4range", isA<String>(), '[1,5)'),
  _Case('daterange', "'[2024-01-01,2024-02-01)'::daterange", isA<String>(),
      '[2024-01-01,2024-02-01)'),
  _Case('enum', "'ok'::eloquent_parity_mood", isA<String>(), 'ok'),
  _Case('domain', "'x'::eloquent_parity_dom", isA<String>(), 'x'),
  // Arrays of these: lists of texts; of user-defined types: the literal.
  _Case('interval[]', "array['1 day'::interval, null]", isA<List<String?>>(),
      ['1 day', null]),
  _Case(
      'inet[]', "array['10.0.0.1'::inet]", isA<List<String?>>(), ['10.0.0.1']),
  _Case(
      'money[]', 'array[1.5::numeric::money]', isA<List<String?>>(), ['1.50']),
  _Case('enum[]', "'{ok,sad}'::eloquent_parity_mood[]", isA<String>(),
      '{ok,sad}'),
  _Case('null', 'null::interval', isA<Object>(), null),
];

Future<Connection> _open(
    Manager manager, String name, Map<String, dynamic> config) async {
  manager.addConnection(config, name);
  return manager.getConnection(name);
}

void main() {
  late Manager manager;

  setUpAll(() async {
    manager = Manager();
    final db = await _open(manager, 'setup', _config('postgres'));
    await db.execute('do \$\$ begin create type eloquent_parity_mood as enum '
        "('ok', 'sad'); exception when duplicate_object then null; end \$\$");
    await db.execute('do \$\$ begin create domain eloquent_parity_dom as text; '
        'exception when duplicate_object then null; end \$\$');
  });

  tearDownAll(() async {
    final db = await manager.getConnection('setup');
    await db.execute('drop type if exists eloquent_parity_mood cascade');
    await db.execute('drop domain if exists eloquent_parity_dom');
    for (final name
        in manager.getDatabaseManager().connectionsProp.keys.toList()) {
      await manager.getDatabaseManager().purge(name);
    }
  });

  void check(String driver, String where, _Case c, Object? value) {
    final reason = '$driver, ${c.name} (${c.sql}), $where';
    if (c.value == null) {
      expect(value, isNull, reason: reason);
      return;
    }
    expect(value, c.type, reason: '$reason: ${value.runtimeType}');
    expect(value, equals(c.value), reason: reason);
  }

  final results = <String, List<Map<String, dynamic>>>{};

  for (final driver in _drivers) {
    group(driver, () {
      test('each type, cold and warm', () async {
        final db = await _open(manager, driver, _config(driver));
        for (final run in ['cold', 'warm', 'warm again']) {
          for (final c in _cases) {
            final row = (await db.select('select ${c.sql} as v')).single;
            check(driver, run, c, row['v']);
          }
        }
      });

      test('every type in one row, and inside a transaction', () async {
        final db = await manager.getConnection(driver);
        final sql = 'select ${[
          for (var i = 0; i < _cases.length; i++) '${_cases[i].sql} as c$i',
        ].join(', ')}';
        final rows = <Map<String, dynamic>>[];
        for (var run = 0; run < 3; run++) {
          rows.add((await db.select(sql)).single);
        }
        rows.add(await db
            .transaction((ctx) async => (await ctx.select(sql)).single));
        for (final row in rows) {
          for (var i = 0; i < _cases.length; i++) {
            check(driver, 'one row', _cases[i], row['c$i']);
          }
        }
        results[driver] = rows;
      });
    });
  }

  test('the four adapters return the same maps', () {
    final reference = results['postgres'];
    expect(reference, isNotNull);
    for (final driver in _drivers) {
      expect(results[driver], equals(reference), reason: driver);
    }
  });

  group("pg_types: 'driver'", () {
    test('keeps each driver its own types', () async {
      final expected = {
        'postgres': 'PgInterval',
        'postgres_v3': 'Interval',
        'dargres': 'String',
        'dpgsql': 'DpgsqlInterval',
      };
      for (final driver in _drivers) {
        final db = await _open(
            manager, '$driver-native', _config(driver, pgTypes: 'driver'));
        final value =
            (await db.select("select '1 day'::interval as v")).single['v'];
        expect(value.runtimeType.toString(), expected[driver], reason: driver);
      }
    });

    test('an unknown pg_types value is rejected', () {
      final config = _config('postgres', pgTypes: 'native')
        ..['schema'] = 'public';
      expect(() => PDOConfig.fromMap(config), throwsArgumentError);
    });
  });

  group('driver_options', () {
    test('an unknown key is rejected with the known ones', () async {
      for (final driver in _drivers) {
        await expectLater(
            _open(manager, '$driver-typo',
                _config(driver, driverOptions: {'statmentCacheCapacity': 1})),
            throwsA(isA<ArgumentError>().having(
                (e) => e.message, 'message', contains('Known options'))),
            reason: driver);
      }
    });

    test('options reach the driver', () async {
      final options = {
        'postgres': {'queryTimeoutInSeconds': 1},
        'postgres_v3': {'queryTimeout': 1},
        'dargres': {'commandTimeout': 1},
        'dpgsql': {'Statement Timeout': 1000},
      };
      for (final driver in _drivers) {
        final db = await _open(manager, '$driver-options',
            _config(driver, driverOptions: options[driver]));
        // A 1 s timeout from driver_options (client or server side).
        await expectLater(db.select('select pg_sleep(3)'), throwsA(anything),
            reason: driver);
      }
    });
  });
}
