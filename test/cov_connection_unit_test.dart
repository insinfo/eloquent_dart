// Unit tests of Connection, DatabaseManager and Migrator over a fake PDO:
// reconnection after a lost connection, pretend, cursor, disconnect,
// outsideTransaction, query listeners and the connection cache.
import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart' show PostgresqlException;
import 'package:eloquent/eloquent.dart';
import 'package:mysql_dart/exception.dart' show MySQLClientException;
import 'package:postgres/postgres.dart' show PgException;
import 'package:postgres_fork/postgres.dart' show PostgreSQLException;
import 'package:test/test.dart';

/// A PDO whose statements only go to [log]. [onQuery] runs instead of the
/// default (log, return a row and one affected row) and may throw.
class _FakePdo extends PDOInterface {
  _FakePdo(this.label, {bool pool = false, int poolSize = 1})
      : config = PDOConfig(
            driver: 'pgsql',
            host: 'localhost',
            database: 'x',
            pool: pool,
            poolSize: poolSize) {
    pdoInstance = this;
  }

  final String label;

  @override
  PDOConfig config;

  /// The statements that reached the server, in order (`begin`, `commit`
  /// and `rollback` for transactions).
  final List<String> log = [];

  /// Runs instead of the default for each statement.
  Future<PDOResults> Function(_FakePdo pdo, String sql)? onQuery;

  bool closed = false;
  Duration closeDelay = Duration.zero;

  @override
  Future<PDOInterface> connect() async => this;

  @override
  Future close() async {
    if (closeDelay > Duration.zero) await Future<void>.delayed(closeDelay);
    closed = true;
  }

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async =>
      (await query(statement)).rowsAffected;

  @override
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) {
    final handler = onQuery;
    if (handler != null) return handler(this, query);
    log.add(query);
    return Future.value(PDOResults([
      {'one': 1}
    ], 1));
  }

  @override
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),
      [int? timeoutInSeconds]) async {
    log.add('begin');
    try {
      final result = await operation(_FakeTx(this));
      log.add('commit');
      return result;
    } catch (_) {
      log.add('rollback');
      rethrow;
    }
  }

  @override
  String toString() => '_FakePdo($label)';
}

class _FakeTx extends PDOTransactionContext {
  _FakeTx(this.parent) {
    pdoInstance = parent;
  }

  final _FakePdo parent;

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) =>
      parent.execute(statement, timeoutInSeconds);

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) =>
      parent.query(query, params, timeoutInSeconds);

  @override
  PDOConfig getConfig() => parent.config;
}

/// dargres' "Connection is closed, cannot execute query." (thrown before the
/// query is queued) prints the server's last notice instead of its message.
class _DargresClosedException implements Exception {
  final String message = 'Connection is closed, cannot execute query.';
  final Object errorCode = 500;
  final String serverErrorCode = '57P01';

  @override
  String toString() => 'PostgresqlException: FATAL 57P01 terminating '
      'connection due to administrator command #dargres_0';
}

/// A connection over [pdo] whose reconnector gives it [fresh] (one per
/// reconnection) and counts the reconnections.
class _Harness {
  _Harness([_FakePdo? pdo]) : pdo = pdo ?? _FakePdo('first') {
    connection = PostgresConnection(this.pdo, 'x', '', {'driver': 'pgsql'});
    connection.setReconnector((c) async {
      final next = _FakePdo('fresh${fresh.length + 1}');
      fresh.add(next);
      c.setPdo(next);
    });
  }

  final _FakePdo pdo;
  late final Connection connection;
  final List<_FakePdo> fresh = [];

  /// Every statement that reached any of the PDOs.
  List<String> get statements => [...pdo.log, for (final f in fresh) ...f.log];
}

/// [pdo] fails the first statement that starts with [prefix] with [error],
/// [afterRunning] (the server ran it, the reply was lost) or not.
void _failOnce(_FakePdo pdo, String prefix, Object error,
    {required bool afterRunning}) {
  var failed = false;
  pdo.onQuery = (p, sql) async {
    if (!failed && sql.startsWith(prefix)) {
      failed = true;
      if (afterRunning) p.log.add(sql);
      throw error;
    }
    p.log.add(sql);
    return PDOResults([
      {'one': 1}
    ], 1);
  };
}

void main() {
  group('lost connection (item 1)', () {
    // The server committed the statement, then the connection dropped
    // before the reply: running it again would write twice.
    final inFlight = <String, Object>{
      'socket reset': const SocketException('Connection reset by peer'),
      'mysql_dart': const MySQLClientException('Connection closed'),
      'dpgsql': StateError('EOF antes de ler 5 bytes'),
      'dargres': PostgresqlException(
          'terminating connection due to administrator command',
          errorCode: '57P01',
          serverErrorCode: '57P01',
          sql: 'insert into t values (1)'),
    };
    for (final MapEntry(key: name, value: error) in inFlight.entries) {
      test('a write lost in flight ($name) runs once, fails and reconnects',
          () async {
        final h = _Harness();
        _failOnce(h.pdo, 'insert', error, afterRunning: true);

        await expectLater(h.connection.insert('insert into t values (1)'),
            throwsA(same(error)));
        expect(h.statements.where((s) => s.startsWith('insert')), hasLength(1),
            reason: 'the committed insert must not run again');
        expect(h.fresh, hasLength(1), reason: 'reconnected for the next call');

        await h.connection.insert('insert into t values (2)');
        expect(h.fresh.single.log, ['insert into t values (2)']);
      });
    }

    test('update, delete, statement, execute and unprepared are not run again',
        () async {
      final calls = <String, Future<dynamic> Function(Connection)>{
        'update t set a = 1': (c) => c.update('update t set a = 1'),
        'delete from t': (c) => c.delete('delete from t'),
        'insert into t default values': (c) =>
            c.statement('insert into t default values'),
        'update t set b = 1': (c) => c.execute('update t set b = 1'),
        'update t set c = 1': (c) => c.unprepared('update t set c = 1'),
        'update t set d = 1 returning *': (c) =>
            c.select('update t set d = 1 returning *', [], false),
      };
      for (final MapEntry(key: sql, value: call) in calls.entries) {
        final h = _Harness();
        _failOnce(h.pdo, sql, const SocketException('Connection reset'),
            afterRunning: true);
        await expectLater(call(h.connection), throwsA(isA<SocketException>()),
            reason: sql);
        expect(h.statements, [sql], reason: sql);
      }
    });

    // A select can have side effects (nextval, a function that writes): it
    // is not run again either once it may have reached the server.
    test('a select lost in flight runs once, fails and reconnects', () async {
      for (final sql in [
        'select 1 as one',
        "select nextval('s') as id",
      ]) {
        final h = _Harness();
        _failOnce(h.pdo, 'select', const SocketException('Connection reset'),
            afterRunning: true);
        await expectLater(
            h.connection.selectOne(sql), throwsA(isA<SocketException>()),
            reason: sql);
        expect(h.statements, [sql], reason: sql);
        expect(h.fresh, hasLength(1), reason: 'reconnected for the next call');
      }
    });

    test('a select refused before it was sent runs on the new connection',
        () async {
      final h = _Harness();
      _failOnce(
          h.pdo,
          'select',
          PgException(
              'Attempting to execute query, but connection is not open.'),
          afterRunning: false);
      expect(await h.connection.select('select 1 as one'), [
        {'one': 1}
      ]);
      expect(h.fresh.single.log, ['select 1 as one']);
    });

    // Issue #2: the server closed the idle connection; the adapter refuses
    // the statement before sending it, so it is safe to run it again.
    test('a write refused before it was sent runs once on the new connection',
        () async {
      final refused = <String, Object>{
        'postgres_fork': PostgreSQLException(
            'Attempting to execute query, but connection is not open.'),
        'postgres_v3':
            PgException('Attempting to execute query, but connection is not '
                'open.'),
        'mysql_dart': const MySQLClientException(
            'Can not execute query: connection closed'),
        'dpgsql': StateError(
            'DpgsqlConnection: the connection to the server was lost.'),
        'dargres (no notice)': PostgresqlException(
            'Connection is closed, cannot execute query.',
            errorCode: 500,
            connectionName: 'dargres_0'),
        'dargres': _DargresClosedException(),
        'idle-session timeout': PostgresqlException(
            'terminating connection due to idle-session timeout',
            errorCode: '57P05',
            serverErrorCode: '57P05',
            sql: 'insert into t values (1)'),
      };
      await Future.wait([
        for (final MapEntry(key: name, value: error) in refused.entries)
          () async {
            final h = _Harness();
            _failOnce(h.pdo, 'insert', error, afterRunning: false);
            await h.connection.insert('insert into t values (1)');
            expect(h.statements, ['insert into t values (1)'], reason: name);
            expect(h.fresh.single.log, ['insert into t values (1)'],
                reason: name);
          }(),
      ]);
    });

    test(
        'concurrent reconnect loops each make tryReconnectLimit attempts '
        '(item 8)', () async {
      final h = _Harness();
      h.connection.tryReconnectLimit = 2;
      final calls = <String, int>{'a': 0, 'b': 0};
      Future<dynamic> callback(Connection c, String q, dynamic b, int? t) {
        calls[q] = calls[q]! + 1;
        throw PgException(
            'Attempting to execute query, but connection is not open.');
      }

      final first = PgException(
          'Attempting to execute query, but connection is not open.');
      final results = await Future.wait([
        for (final q in ['a', 'b'])
          h.connection
              .tryAgainIfCausedByLostConnection(first, q, [], callback, null,
                  delay: 5)
              .then((_) => 'ok', onError: (Object e) => 'failed'),
      ]);
      expect(results, ['failed', 'failed']);
      expect(calls, {'a': 2, 'b': 2});
    });
  });

  group('pretend (item 2)', () {
    test('does not pretend the queries of another request', () async {
      final pdo = _FakePdo('w');
      final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});
      final inside = Completer<void>();
      final release = Completer<void>();

      final pretended = db.pretend((Connection c) async {
        await c.insert('insert into t values (1)');
        inside.complete();
        await release.future;
      });
      await inside.future;
      // Another request on the same connection, while the pretend runs.
      await db.insert('insert into t values (2)');
      release.complete();

      final log = await pretended;
      expect(pdo.log, ['insert into t values (2)']);
      expect(log.map((q) => q['query']), ['insert into t values (1)']);
      expect(db.pretending(), isFalse);
    });

    test('a nested pretend keeps the outer one pretending', () async {
      final pdo = _FakePdo('w');
      final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});
      late List inner;
      final outer = await db.pretend((Connection c) async {
        inner = await c.pretend((Connection c) async {
          await c.insert('insert into t values (1)');
        });
        expect(c.pretending(), isTrue);
        await c.insert('insert into t values (2)');
      });
      expect(pdo.log, isEmpty, reason: 'nothing reaches the database');
      expect(inner.map((q) => q['query']), ['insert into t values (1)']);
      expect(outer.map((q) => q['query']), ['insert into t values (2)']);
      expect(db.pretending(), isFalse);
    });

    test('keeps the query log of the connection', () async {
      final pdo = _FakePdo('w');
      final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'})
        ..enableQueryLog();
      await db.select('select 1');
      final log = await db.pretend((Connection c) => c.delete('delete from t'));
      expect(log, hasLength(1));
      expect(db.getQueryLog().map((q) => q['query']), ['select 1']);
      expect(db.logging(), isTrue);
    });

    test('accepts a callback without parameters', () async {
      final pdo = _FakePdo('w');
      final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});
      final List<Map<String, dynamic>> log =
          await db.pretend(() => db.delete('delete from t'));
      expect(log.single['query'], 'delete from t');
      expect(pdo.log, isEmpty);
    });
  });

  group('cursor() SQL fallback', () {
    void serveCursor(_FakePdo pdo, {Duration closeDelay = Duration.zero}) {
      var fetches = 0;
      pdo.onQuery = (p, sql) async {
        if (sql.startsWith('close') && closeDelay > Duration.zero) {
          await Future<void>.delayed(closeDelay);
        }
        p.log.add(sql.split(' ').first);
        if (sql.startsWith('fetch')) {
          return PDOResults(
              fetches++ == 0
                  ? [
                      {'id': 1},
                      {'id': 2}
                    ]
                  : [],
              0);
        }
        return PDOResults([], 0);
      };
    }

    test('runs on the read PDO it was asked for (item 3)', () async {
      final write = _FakePdo('write');
      final read = _FakePdo('read');
      serveCursor(read);
      final db = PostgresConnection(write, 'x', '', {'driver': 'pgsql'})
        ..setReadPdo(read);

      final rows = await db.cursor('select id from t', [], true, 2).toList();
      expect(rows, [
        {'id': 1},
        {'id': 2}
      ]);
      expect(write.log, isEmpty);
      expect(
          read.log, ['begin', 'declare', 'fetch', 'fetch', 'close', 'commit']);
    });

    test('cancelling waits until the cursor is closed (item 13)', () async {
      final pdo = _FakePdo('w');
      serveCursor(pdo, closeDelay: const Duration(milliseconds: 50));
      final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});

      await for (final row in db.cursor('select id from t', [], true, 2)) {
        expect(row, {'id': 1});
        break; // cancels the subscription and waits for it
      }
      expect(pdo.log.last, 'commit');
      expect(pdo.log.where((s) => s == 'close'), hasLength(1));
    });
  });

  test('disconnect() closes the write and the read PDO (item 4)', () async {
    final write = _FakePdo('write');
    final read = _FakePdo('read');
    final db = PostgresConnection(write, 'x', '', {'driver': 'pgsql'})
      ..setReadPdo(read);
    await db.disconnect();
    expect(write.closed, isTrue);
    expect(read.closed, isTrue);
  });

  group('outsideTransaction() in a transactionScope (item 5)', () {
    Connection pooled(int size) => PostgresConnection(
        _FakePdo('w', pool: true, poolSize: size),
        'x',
        '',
        {'driver': 'pgsql', 'pool': true, 'poolsize': size});

    test('throws with a pool of one connection', () async {
      final db = pooled(1);
      await expectLater(
          db.transactionScope(
              (ctx) => db.outsideTransaction(() async => 'outside')),
          throwsA(isA<StateError>()));
    });

    test('runs with a pool of two connections', () async {
      final db = pooled(2);
      expect(
          await db.transactionScope(
              (ctx) => db.outsideTransaction(() async => 'outside')),
          'outside');
    });
  });

  test('setTablePrefix() also updates the schema grammar (item 6)', () {
    final db = PostgresConnection(_FakePdo('w'), 'x', '', {'driver': 'pgsql'});
    db.getSchemaBuilder();
    db.setTablePrefix('p_');
    expect(db.getQueryGrammar().getTablePrefix(), 'p_');
    expect(db.getSchemaGrammar().getTablePrefix(), 'p_');
  });

  test('getElapsedTime() is in milliseconds (item 7)', () {
    final db = PostgresConnection(_FakePdo('w'), 'x', '', {'driver': 'pgsql'});
    final elapsed = db.getElapsedTime(Utils.microtime() - 50000) as num;
    expect(elapsed, inInclusiveRange(50, 5000));
  });

  test('a listener that throws does not fail the query (item 10)', () async {
    final pdo = _FakePdo('w');
    final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});
    final seen = <String>[];
    final handled = <Object>[];
    db.listen((q) => throw StateError('listener failed'));
    db.listen((q) => throw StateError('handled'), onError: (e, s) {
      handled.add(e);
    });
    db.listen((q) => seen.add(q.sql));
    final uncaught = <Object>[];
    final printed = <String>[];
    final done = Completer<Object?>();
    runZonedGuarded(() async {
      try {
        done.complete(await db.insert('insert into t values (1)'));
      } catch (e) {
        done.complete(e);
      }
    }, (error, stack) => uncaught.add(error),
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printed.add(line)));
    final result = await done.future;
    expect(result, isA<PDOResults>());
    expect(pdo.log, ['insert into t values (1)']);
    expect(seen, ['insert into t values (1)'],
        reason: 'the other listeners are still called');
    // An uncaught error in the root zone ends the program: a failing log
    // listener must not take a server down.
    expect(uncaught, isEmpty);
    expect(handled.single, isA<StateError>());
    expect(printed.join(), contains('listener failed'));
  });

  test('disconnect() closes the PDOs it started with', () async {
    final write = _FakePdo('write')
      ..closeDelay = const Duration(milliseconds: 20);
    final read = _FakePdo('read');
    final db = PostgresConnection(write, 'x', '', {'driver': 'pgsql'})
      ..setReadPdo(read);
    final closing = db.disconnect();
    // A reconnection gives the connection new PDOs meanwhile.
    final freshRead = _FakePdo('fresh read');
    db.setReadPdo(freshRead);
    await closing;
    expect(read.closed, isTrue);
    expect(freshRead.closed, isFalse, reason: 'the new PDO stays open');
  });

  test('a query started in a pretend and run after it is not pretended',
      () async {
    final pdo = _FakePdo('w');
    final db = PostgresConnection(pdo, 'x', '', {'driver': 'pgsql'});
    final late = Completer<void>();
    late Future<void> leftover;
    await db.pretend(() async {
      leftover = late.future.then((_) => db.insert('insert into late'));
    });
    // Another pretend is running when the leftover query runs: it must not
    // decide whether that query is pretended.
    final other = Completer<void>();
    final otherPretend = db.pretend(() => other.future);
    late.complete();
    await leftover;
    other.complete();
    await otherPretend;
    expect(pdo.log, ['insert into late']);
  });

  group('DatabaseManager (item 12)', () {
    late Manager manager;
    late DatabaseManager dm;
    late List<Connection> made;

    setUp(() {
      made = [];
      manager = Manager()
        ..addConnection({'driver': 'fake'})
        ..addConnection({'driver': 'fake'}, 'x');
      dm = manager.getDatabaseManager();
      dm.extend('fake', (Map<String, dynamic> config, String name) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final write = _FakePdo('$name-w${made.length}')
          ..closeDelay = const Duration(milliseconds: 30);
        final read = _FakePdo('$name-r${made.length}')
          ..closeDelay = const Duration(milliseconds: 30);
        final c = PostgresConnection(
            write, 'x', '', {...config, 'name': name, 'driver': 'pgsql'})
          ..setReadPdo(read);
        made.add(c);
        return c;
      });
    });

    test('purge() without a name forgets the default connection', () async {
      final first = await dm.connection();
      await dm.purge();
      expect((first.pdo as _FakePdo).closed, isTrue);
      final second = await dm.connection();
      expect(identical(first, second), isFalse);
    });

    test('reconnect() waits for the old connection to close', () async {
      final db = await dm.connection('x');
      final old = db.pdo as _FakePdo;
      await dm.reconnect('x');
      expect(old.closed, isTrue);
      expect(identical(db.pdo, old), isFalse);
    });

    test('::read and ::write work after the connection was made', () async {
      final read = await dm.connection('x::read');
      expect((read.pdo as _FakePdo).label, contains('-r'));
      final plain = await dm.connection('x');
      expect((plain.pdo as _FakePdo).label, contains('-w'));
      expect((plain.getReadPdo() as _FakePdo).label, contains('-r'));
      final write = await dm.connection('x::write');
      expect((write.getReadPdo() as _FakePdo).label, contains('-w'));
    });

    test('a ::read connection reconnects as ::read', () async {
      final read = await dm.connection('x::read');
      final before = read.pdo;
      await read.reconnect();
      expect((read.pdo as _FakePdo).label, contains('-r'));
      expect(identical(read.pdo, before), isFalse, reason: 'a new PDO');
      expect((before as _FakePdo).closed, isTrue);
    });

    test('concurrent reconnections make one new connection', () async {
      final db = await dm.connection('x');
      final old = db.pdo as _FakePdo;
      await Future.wait([dm.reconnect('x'), dm.reconnect('x')]);
      expect(made, hasLength(2), reason: 'the first and one reconnection');
      expect(old.closed, isTrue);
      expect(identical(db.pdo, made.last.pdo), isTrue);
    });

    test('concurrent first calls make one connection', () async {
      final both = await Future.wait([dm.connection('x'), dm.connection('x')]);
      expect(identical(both[0], both[1]), isTrue);
      expect(made, hasLength(1));
    });
  });

  group('Migrator pretend (item 11)', () {
    late Manager manager;
    late _FakePdo pdo;

    Migrator migrator(Map<String, dynamic> config) {
      pdo = _FakePdo('w');
      manager = Manager()..addConnection({...config, 'driver': 'fake'});
      final dm = manager.getDatabaseManager();
      dm.extend(
          'fake',
          (Map<String, dynamic> c, String name) async => PostgresConnection(
              pdo, 'x', '', {...c, 'name': name, 'driver': 'pgsql'}));
      return Migrator(_NoRepository(), dm, {
        '2026_01_01_000000_cov_cx_create': () => _CreateTable(),
      });
    }

    test('without a pretend option only notes what would run', () async {
      final m = migrator({});
      await m
          .runMigrationList(['2026_01_01_000000_cov_cx_create'], pretend: true);
      expect(m.notes, contains(' -> Would run up() method.'));
      expect(pdo.log, isEmpty);
    });

    test("with 'pretend': true notes the queries without running them",
        () async {
      final m = migrator({'pretend': true});
      await m
          .runMigrationList(['2026_01_01_000000_cov_cx_create'], pretend: true);
      expect(m.notes.join('\n'), contains('create table cov_cx_pretend'));
      expect(pdo.log, isEmpty);
    });
  });
}

class _CreateTable extends Migration {
  @override
  Future<void> up() => statement('create table cov_cx_pretend (id int)');

  @override
  Future<void> down() => statement('drop table cov_cx_pretend');
}

class _NoRepository implements MigrationRepositoryInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
