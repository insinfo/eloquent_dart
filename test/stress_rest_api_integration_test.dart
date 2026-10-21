// Stress test: a small REST API on dart:io HttpServer, served by several
// isolates sharing one port (`shared: true`), each with its own eloquent
// Connection, and several client isolates using HttpClient that write and
// read concurrently. Runs on postgres, postgres_v3, dargres, dpgsql and
// mysql, with and without pool. dargres, dpgsql and mysql also run on a
// single connection with the adapter's lock off: the driver alone queues the
// concurrent callers (and keeps them out of each other's transactions).
//
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
// Size: STRESS_SERVERS (4), STRESS_CLIENTS (6), STRESS_ITEMS (20 per
// client), STRESS_INCREMENTS (3 per item), STRESS_POOL_SIZE (4).
@Tags(['integration', 'stress'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:eloquent/eloquent.dart';
// ignore: implementation_imports
import 'package:eloquent/src/pdo/core/operation_lock.dart';
import 'package:test/test.dart';

int _env(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

final _servers = _env('STRESS_SERVERS', 4);
final _clients = _env('STRESS_CLIENTS', 6);
final _items = _env('STRESS_ITEMS', 20);
final _increments = _env('STRESS_INCREMENTS', 3);
final _poolSize = _env('STRESS_POOL_SIZE', 4);

Map<String, dynamic> _config(String driver, bool pool) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'pool': pool,
        'poolsize': _poolSize,
      }
    : {
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
        'pool': pool,
        'poolsize': _poolSize,
      };

// ------------------------------------------------------------------ server

/// One server isolate: binds the shared port, serves until told to stop,
/// then reports the errors it hit.
Future<void> _serverMain(List<Object?> args) async {
  final config = Map<String, dynamic>.from(args[0] as Map);
  final port = args[1] as int;
  final ready = args[2] as SendPort;
  OperationLock.enabled = args[3] as bool;

  final manager = Manager()..addConnection(config, 'api');
  final db = await manager.getConnection('api');
  final server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
  final errors = <String>[];
  final pending = <Future<void>>{};
  final commands = ReceivePort();

  final subscription = server.listen((request) {
    final future = _handle(db, request, errors);
    pending.add(future);
    future.whenComplete(() => pending.remove(future));
  });
  ready.send([server.port, commands.sendPort]);

  final stop = await commands.first as SendPort;
  await server.close();
  await subscription.cancel();
  await Future.wait(pending);
  await manager.getDatabaseManager().purge('api');
  stop.send(errors);
}

Future<void> _handle(
    Connection db, HttpRequest request, List<String> errors) async {
  final response = request.response;
  var status = 200;
  Object? body;
  try {
    final path = request.uri.pathSegments;
    switch ((request.method, path)) {
      // Create an item and bump the counter in one transaction.
      case ('POST', ['items']):
        final data = await _json(request);
        final id = await db.transaction((ctx) async {
          final id = await ctx.table('stress_items').insertGetId({
            'client': data['client'],
            'name': data['name'],
            'qty': 0,
            'created_at': DateTime.now(),
          });
          await ctx.table('stress_counter').where('id', 1).increment('total');
          return id;
        });
        status = 201;
        body = {'id': _asInt(id)};
      case ('GET', ['items', final id]):
        final row = await db
            .table2('stress_items')
            .select(['id', 'client', 'name', 'qty'])
            .where('id', int.parse(id))
            .first();
        if (row == null) {
          status = 404;
        } else {
          body = {
            'id': _asInt(row['id']),
            'client': _asInt(row['client']),
            'name': row['name'],
            'qty': _asInt(row['qty']),
          };
        }
      case ('POST', ['items', final id, 'increment']):
        body = {
          'affected': await db
              .table('stress_items')
              .where('id', int.parse(id))
              .increment('qty'),
        };
      // insertGetId outside a transaction: on a pool the generated id must
      // come from the same connection as the insert.
      case ('POST', ['notes']):
        final data = await _json(request);
        final id =
            await db.table('stress_notes').insertGetId({'text': data['text']});
        status = 201;
        body = {'id': _asInt(id)};
      case ('GET', ['notes', final id]):
        final text = await db
            .table2('stress_notes')
            .where('id', int.parse(id))
            .value<String>('text');
        if (text == null) {
          status = 404;
        } else {
          body = {'text': text};
        }
      default:
        status = 404;
    }
  } catch (error) {
    errors.add('${request.method} ${request.uri}: $error');
    status = 500;
    body = {'error': '$error'};
  }
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<Map<String, dynamic>> _json(HttpRequest request) async =>
    jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;

int _asInt(Object? value) => value is int ? value : int.parse('$value');

// ------------------------------------------------------------------ client

/// One client isolate: creates its items, reads them back, increments them
/// concurrently, checks the totals, and writes and reads notes.
Future<void> _clientMain(List<Object?> args) async {
  final port = args[0] as int;
  final clientId = args[1] as int;
  final items = args[2] as int;
  final increments = args[3] as int;
  final reply = args[4] as SendPort;

  final http = HttpClient()..maxConnectionsPerHost = 8;
  final errors = <String>[];
  var requests = 0;

  Future<(int, Map<String, dynamic>?)> call(String method, String path,
      [Object? body]) async {
    requests++;
    final request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(text);
    return (response.statusCode, decoded as Map<String, dynamic>?);
  }

  void check(bool ok, String what) {
    if (!ok) errors.add('client $clientId: $what');
  }

  Future<void> item(int i) async {
    final name = 'c$clientId-i$i-ação';
    final (created, createdBody) =
        await call('POST', '/items', {'client': clientId, 'name': name});
    check(created == 201, 'create $name -> $created $createdBody');
    if (created != 201) return;
    final id = createdBody!['id'] as int;

    final (read, row) = await call('GET', '/items/$id');
    check(read == 200 && row!['name'] == name && row['qty'] == 0,
        'read $id -> $read $row');

    final bumps = await Future.wait([
      for (var k = 0; k < increments; k++) call('POST', '/items/$id/increment'),
    ]);
    for (final (status, result) in bumps) {
      check(status == 200 && result!['affected'] == 1,
          'increment $id -> $status $result');
    }

    final (reread, after) = await call('GET', '/items/$id');
    check(reread == 200 && after!['qty'] == increments,
        'qty of $id -> $reread $after (expected $increments)');

    final note = 'nota $clientId/$i';
    final (noted, noteBody) = await call('POST', '/notes', {'text': note});
    check(noted == 201, 'note -> $noted $noteBody');
    if (noted == 201) {
      final noteId = noteBody!['id'];
      final (got, gotBody) = await call('GET', '/notes/$noteId');
      check(got == 200 && gotBody!['text'] == note,
          'note $noteId -> $got $gotBody (expected "$note")');
    }
  }

  try {
    // Four items in flight at a time, each with parallel increments.
    for (var start = 0; start < items; start += 4) {
      await Future.wait([
        for (var i = start; i < start + 4 && i < items; i++) item(i),
      ]);
    }
  } catch (error) {
    errors.add('client $clientId: $error');
  } finally {
    http.close(force: true);
  }
  reply.send([requests, errors]);
}

// -------------------------------------------------------------------- test

Future<T> _spawn<T>(void Function(List<Object?>) entry,
    List<Object?> Function(SendPort) args) async {
  final port = ReceivePort();
  await Isolate.spawn(entry, args(port.sendPort));
  final result = await port.first as T;
  port.close();
  return result;
}

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    for (final (pool, adapterLock) in [
      (true, true),
      (false, true),
      if (driver != 'postgres' && driver != 'postgres_v3') (false, false),
    ]) {
      final mysql = driver == 'mysql';
      final mode = pool
          ? 'pool'
          : adapterLock
              ? 'single connection'
              : 'single connection, driver queue only';
      test('$driver $mode: $_servers servers, $_clients clients', () async {
        final manager = Manager()
          ..addConnection(_config(driver, pool), 'setup');
        final db = await manager.getConnection('setup');
        final serial =
            mysql ? 'int AUTO_INCREMENT PRIMARY KEY' : 'serial PRIMARY KEY';
        final timestamp = mysql ? 'datetime' : 'timestamp';
        for (final table in [
          'stress_items',
          'stress_counter',
          'stress_notes'
        ]) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
        await db.execute('CREATE TABLE stress_items (id $serial, client int, '
            'name varchar(60), qty int, created_at $timestamp)');
        await db.execute(
            'CREATE TABLE stress_counter (id int PRIMARY KEY, total int)');
        await db.execute(
            'CREATE TABLE stress_notes (id $serial, text varchar(60))');
        await db.table('stress_counter').insert({'id': 1, 'total': 0});

        // Servers: the first binds an ephemeral port, the others share it.
        final config = _config(driver, pool);
        final first = await _spawn<List>(
            _serverMain, (ready) => [config, 0, ready, adapterLock]);
        final port = first[0] as int;
        final serverCommands = <SendPort>[first[1] as SendPort];
        for (var s = 1; s < _servers; s++) {
          final started = await _spawn<List>(
              _serverMain, (ready) => [config, port, ready, adapterLock]);
          serverCommands.add(started[1] as SendPort);
        }

        final watch = Stopwatch()..start();
        final results = await Future.wait([
          for (var c = 0; c < _clients; c++)
            _spawn<List>(
                _clientMain, (reply) => [port, c, _items, _increments, reply]),
        ]);
        watch.stop();

        final serverErrors = <String>[];
        for (final commands in serverCommands) {
          final stopped = ReceivePort();
          commands.send(stopped.sendPort);
          serverErrors.addAll((await stopped.first as List).cast<String>());
          stopped.close();
        }

        final requests = results.fold<int>(0, (sum, r) => sum + (r[0] as int));
        final clientErrors = [
          for (final r in results) ...(r[1] as List).cast<String>(),
        ];
        printOnFailure('$requests requests in ${watch.elapsed}');

        expect(serverErrors, isEmpty, reason: serverErrors.take(5).join('\n'));
        expect(clientErrors, isEmpty, reason: clientErrors.take(5).join('\n'));

        final created = _clients * _items;
        expect(await db.table('stress_items').count(), created);
        expect((await db.table('stress_items').sum('qty'))!.toInt(),
            created * _increments);
        expect(await db.table('stress_counter').where('id', 1).value('total'),
            created,
            reason: 'counter updated inside every create transaction');
        expect(await db.table('stress_notes').count(), created);
        expect(
            await db
                .table('stress_items')
                .select(['client'])
                .groupBy('client')
                .count(),
            _clients);

        for (final table in [
          'stress_items',
          'stress_counter',
          'stress_notes'
        ]) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
        await manager.getDatabaseManager().purge('setup');
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
