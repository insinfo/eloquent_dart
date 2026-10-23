// Load test in the style of the new_sali backend: an HTTP server on several
// isolates sharing one port (Angel's Runner with `-j`), a DatabaseService
// that either shares one pooled Connection among all the requests of an
// isolate or opens a new Manager and connection per request and disconnects
// it at the end (runWithDbConnection), and handlers that use what new_sali
// uses: transactions, insertGetId, lockForUpdate, nextValue, savepoints,
// createOrFirst, pagination, an SQL error inside a transaction and Active
// Record models. Client isolates bombard it with many requests in flight
// and check every answer; then the database is checked for lost or
// duplicated writes and the connections for leaks.
//
// Requires localhost:5432, database `banco_teste`, dart/dart.
// Size (small by default, for the CI): NS_DRIVERS (postgres,postgres_v3),
// NS_SERVERS (2), NS_CLIENTS (2), NS_INFLIGHT (4 per client), NS_OPS (40 per
// client), NS_POOL_SIZE (4). A heavier run:
//   NS_DRIVERS=postgres,postgres_v3,dargres,dpgsql NS_SERVERS=4 NS_CLIENTS=8 //   NS_INFLIGHT=32 NS_OPS=300 dart test test/stress_newsali_style_integration_test.dart
// NS_TOLERATE_OVERLOAD=1 accepts the server refusing connections (SQLSTATE
// 53300, more than max_connections without pool) and checks the rest.
@Tags(['integration', 'stress'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

int _env(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

final _drivers =
    (Platform.environment['NS_DRIVERS'] ?? 'postgres,postgres_v3').split(',');
final _servers = _env('NS_SERVERS', 2);
final _clients = _env('NS_CLIENTS', 2);
final _inFlight = _env('NS_INFLIGHT', 4);
final _ops = _env('NS_OPS', 40);
final _poolSize = _env('NS_POOL_SIZE', 4);
final _tolerateOverload = _env('NS_TOLERATE_OVERLOAD', 0) == 1;

/// "too many clients": the server refused the connection.
bool _overloaded(Object? error) => '$error'.contains('53300');

const _year = 2026;
const _tagSlugs = ['urgente', 'sigiloso', 'saude', 'obras', 'educacao'];

Map<String, dynamic> _config(String driver, bool pool) => {
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
      'timezone': 'America/Sao_Paulo',
      'application_name': 'eloquent_ns_stress',
    };

// ------------------------------------------------------- new_sali's pieces

/// new_sali's DatabaseService: one Manager (and pooled Connection) for the
/// isolate, or a new Manager per call.
class DatabaseService {
  DatabaseService(this.config);

  final Map<String, dynamic> config;
  bool get usePool => config['pool'] == true;

  late final Manager _manager = Manager()..addConnection(config, 'default');

  Future<Connection> connect() async {
    if (usePool) return _manager.getConnection('default');
    final manager = Manager()..addConnection(config, 'default');
    return manager.getConnection('default');
  }

  Future<void> close() async {
    if (usePool) await _manager.getDatabaseManager().purge('default');
  }
}

/// new_sali's runWithDbConnection (withDbMiddleware): every request gets a
/// connection; without pool it is disconnected at the end.
Future<T> runWithDbConnection<T>(
    DatabaseService service, Future<T> Function(Connection conn) run) async {
  Connection? conn;
  try {
    conn = await service.connect();
    return await run(conn);
  } finally {
    if (!service.usePool) await conn?.disconnect();
  }
}

class Pessoa extends Model<Pessoa> {
  static final definition = ModelDefinition<Pessoa>(
      table: 'ns_pessoa', create: Pessoa.new, fillable: ['nome']);

  @override
  ModelDefinition<Pessoa> get modelDefinition => definition;

  static ModelQuery<Pessoa> query(Connection db) => definition.query(db);

  int? id;
  String nome = '';
  int versao = 0;

  @override
  Map<String, dynamic> toMap() => {'id': id, 'nome': nome, 'versao': versao};

  @override
  void fill(Map<String, dynamic> row) {
    id = row['id'] as int?;
    nome = row['nome'] as String;
    versao = row['versao'] as int;
  }
}

class _Rollback implements Exception {}

class _Refused implements Exception {}

// ------------------------------------------------------------------ server

Future<void> _serverMain(List<Object?> args) async {
  final config = Map<String, dynamic>.from(args[0] as Map);
  final port = args[1] as int;
  final ready = args[2] as SendPort;

  final service = DatabaseService(config);
  final server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
  final unexpected = <String>[];
  final pending = <Future<void>>{};
  final commands = ReceivePort();

  final subscription = server.listen((request) {
    final future = _handle(service, request, unexpected);
    pending.add(future);
    future.whenComplete(() => pending.remove(future));
  });
  ready.send([server.port, commands.sendPort]);

  final stop = await commands.first as SendPort;
  await server.close();
  await subscription.cancel();
  await Future.wait(pending);
  await service.close();
  stop.send(unexpected);
}

Future<void> _handle(DatabaseService service, HttpRequest request,
    List<String> unexpected) async {
  final response = request.response;
  var status = 200;
  Object? body;
  final path = request.uri.pathSegments;
  final route = (request.method, path);
  try {
    final data = request.method == 'GET' ? const {} : await _json(request);
    body = await runWithDbConnection(service, (db) async {
      switch (route) {
        case ('GET', ['ping']):
          return {'pong': true};

        // Opening: a number per year under an advisory lock, the process,
        // its first step and a global counter, in one transaction.
        case ('POST', ['processos']):
          return db.transaction((ctx) async {
            final codigo = await ctx
                .table('ns_processo')
                .where('ano', '=', _year)
                .nextValue('codigo');
            final id = await ctx.table('ns_processo').insertGetId({
              'ano': _year,
              'codigo': codigo,
              'assunto': data['assunto'],
              'situacao': 'aberto',
            });
            await ctx
                .table('ns_andamento')
                .insert({'processo_id': id, 'seq': 1, 'descricao': 'abertura'});
            await ctx
                .table('ns_contador')
                .where('id', '=', 1)
                .increment('total');
            status = 201;
            return {'id': _asInt(id), 'codigo': codigo};
          });

        case ('GET', ['processos', final id]):
          final processo =
              await db.table2('ns_processo').where('id', int.parse(id)).first();
          if (processo == null) {
            status = 404;
            return null;
          }
          final andamentos = await db
              .table2('ns_andamento')
              .where('processo_id', int.parse(id))
              .count();
          return {
            'id': _asInt(processo['id']),
            'assunto': processo['assunto'],
            'andamentos': andamentos,
          };

        // A step: the row locked, the next number, the new state, and an
        // audit row in a savepoint that is rolled back for every third step.
        case ('POST', ['processos', final id, 'tramitar']):
          return db.transaction((ctx) async {
            final processoId = int.parse(id);
            final row = await ctx
                .table('ns_processo')
                .where('id', '=', processoId)
                .lockForUpdate()
                .first();
            if (row == null) throw StateError('processo $id not found');
            final seq = await ctx
                .table('ns_andamento')
                .where('processo_id', '=', processoId)
                .nextValue('seq');
            await ctx.table('ns_andamento').insert({
              'processo_id': processoId,
              'seq': seq,
              'descricao': 'tramite $seq',
            });
            await ctx
                .table('ns_processo')
                .where('id', '=', processoId)
                .update({'situacao': 'tramite'});
            try {
              await ctx.transaction((nested) async {
                await nested.table('ns_auditoria').insert(
                    {'processo_id': processoId, 'descricao': 'tramite $seq'});
                if (seq % 3 == 0) throw _Rollback();
              });
            } on _Rollback {
              // only the audit row is undone
            }
            return {'seq': seq};
          });

        case ('GET', ['processos']):
          final page = await db
              .table('ns_processo')
              .where('situacao', '<>', 'arquivado')
              .orderBy('id', 'desc')
              .paginate(perPage: 10, page: 1);
          return {'total': page.total(), 'items': page.items().length};

        // Every client asks for the same few slugs at the same time.
        case ('POST', ['tags']):
          final tag = await db
              .table('ns_tag')
              .createOrFirst({'slug': data['slug']}, {'nome': data['slug']});
          return {'id': _asInt(tag['id']), 'slug': tag['slug']};

        // An SQL error after a write: the whole transaction is rolled back
        // and the connection (shared, with a pool) must keep working.
        case ('POST', ['falha']):
          await db.transaction((ctx) async {
            await ctx.table('ns_auditoria').insert({'descricao': 'falha'});
            await ctx.select('select 1 / 0');
          });
          return {'unreachable': true};

        case ('POST', ['pessoas']):
          final pessoa = Pessoa.definition.make(db)..assign(data.cast());
          await pessoa.save();
          status = 201;
          return {'id': pessoa.id};

        case ('PATCH', ['pessoas', final id]):
          final pessoa = await Pessoa.query(db).findOrFail(int.parse(id));
          pessoa
            ..nome = data['nome'] as String
            ..versao += 1;
          await pessoa.save();
          return {'id': pessoa.id, 'nome': pessoa.nome};

        default:
          status = 404;
          return null;
      }
    });
  } catch (error) {
    status = 500;
    body = {'error': '$error'};
    // The SQLSTATE: the message is in the server's language.
    final expected = (request.method == 'POST' &&
            request.uri.path == '/falha' &&
            '$error'.contains('22012')) ||
        (_tolerateOverload && _overloaded(error));
    if (!expected) unexpected.add('${request.method} ${request.uri}: $error');
  }
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<Map<String, dynamic>> _json(HttpRequest request) async {
  final text = await utf8.decoder.bind(request).join();
  return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
}

int _asInt(Object? value) => value is int ? value : int.parse('$value');

// ------------------------------------------------------------------ client

/// One client isolate: [_inFlight] workers send a random mix of requests
/// and check each answer. Reports what it expects to find in the database.
Future<void> _clientMain(List<Object?> args) async {
  final port = args[0] as int;
  final clientId = args[1] as int;
  final reply = args[2] as SendPort;

  final http = HttpClient()..maxConnectionsPerHost = _inFlight;
  final random = Random(clientId);
  final errors = <String>[];
  final processos = <int>[]; // created by this client
  final steps = <int, List<int>>{}; // processo -> seqs answered
  var audits = 0; // steps whose audit row was kept
  final pessoas = <int>[];
  final tagIds = <String, int>{};
  var requests = 0;
  var failures = 0;
  var refused = 0;

  Future<(int, Map<String, dynamic>?)> call(String method, String path,
      [Object? body]) async {
    requests++;
    final request =
        await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(text) as Map<String, dynamic>?;
    if (_tolerateOverload &&
        response.statusCode == 500 &&
        _overloaded(decoded?['error'])) {
      refused++;
      throw _Refused();
    }
    return (response.statusCode, decoded);
  }

  void check(bool ok, String what) {
    if (!ok) errors.add('client $clientId: $what');
  }

  Future<void> attempt(int n) async {
    final roll = random.nextInt(100);
    if (roll < 25 || processos.isEmpty) {
      final (status, body) =
          await call('POST', '/processos', {'assunto': 'c$clientId-$n-ação'});
      check(status == 201, 'open -> $status $body');
      if (status == 201) {
        final id = body!['id'] as int;
        processos.add(id);
        steps[id] = [];
      }
    } else if (roll < 45) {
      final id = processos[random.nextInt(processos.length)];
      final expected = steps[id]!.length + 1;
      final (status, body) = await call('GET', '/processos/$id');
      check(status == 200 && (body!['andamentos'] as int) >= expected,
          'read $id -> $status $body (at least $expected steps)');
    } else if (roll < 65) {
      final id = processos[random.nextInt(processos.length)];
      final (status, body) = await call('POST', '/processos/$id/tramitar');
      check(status == 200, 'step $id -> $status $body');
      if (status == 200) {
        final seq = body!['seq'] as int;
        steps[id]!.add(seq);
        if (seq % 3 != 0) audits++;
      }
    } else if (roll < 73) {
      final (status, body) = await call('GET', '/processos');
      check(status == 200 && body!['total'] is int, 'list -> $status $body');
    } else if (roll < 81) {
      final slug = _tagSlugs[random.nextInt(_tagSlugs.length)];
      final (status, body) = await call('POST', '/tags', {'slug': slug});
      check(status == 200 && body!['slug'] == slug, 'tag -> $status $body');
      if (status == 200) {
        final id = body!['id'] as int;
        final known = tagIds.putIfAbsent(slug, () => id);
        check(known == id, 'tag $slug has ids $known and $id');
      }
    } else if (roll < 84) {
      final (status, body) = await call('POST', '/falha', {});
      check(status == 500, 'failure -> $status $body');
      failures++;
    } else if (roll < 91 || pessoas.isEmpty) {
      final (status, body) = await call(
          'POST', '/pessoas', {'nome': 'p$clientId-$n', 'versao': 99});
      check(status == 201, 'person -> $status $body');
      if (status == 201) pessoas.add(body!['id'] as int);
    } else if (roll < 98) {
      final id = pessoas[random.nextInt(pessoas.length)];
      final (status, body) =
          await call('PATCH', '/pessoas/$id', {'nome': 'p$clientId-$n-b'});
      check(status == 200 && body!['id'] == id, 'update person -> $status');
    } else {
      final (status, _) = await call('GET', '/ping');
      check(status == 200, 'ping -> $status');
    }
  }

  Future<void> operation(int n) async {
    try {
      await attempt(n);
    } on _Refused {
      // the server refused the connection: nothing was written
    }
  }

  try {
    var next = 0;
    await Future.wait([
      for (var w = 0; w < _inFlight; w++)
        () async {
          while (next < _ops) {
            await operation(next++);
          }
        }(),
    ]);
  } catch (error, stack) {
    errors.add('client $clientId: $error\n$stack');
  } finally {
    http.close(force: true);
  }
  reply.send({
    'requests': requests,
    'failures': failures,
    'refused': refused,
    'errors': errors,
    'steps': {for (final e in steps.entries) '${e.key}': e.value},
    'audits': audits,
    'pessoas': pessoas,
    'tags': tagIds,
  });
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

Future<int> _connections(Connection db) async => _asInt((await db.selectOne(
    'select count(*) as n from pg_stat_activity '
    'where datname = current_database() and pid <> pg_backend_pid()'))!['n']);

const _tables = [
  'ns_andamento',
  'ns_auditoria',
  'ns_processo',
  'ns_contador',
  'ns_tag',
  'ns_pessoa',
];

void main() {
  for (final driver in _drivers) {
    for (final pool in [true, false]) {
      final mode = pool ? 'pool of $_poolSize' : 'a connection per request';
      test(
          '$driver, $mode: $_servers servers, $_clients clients x '
          '$_inFlight in flight', () async {
        final manager = Manager()..addConnection(_config(driver, true), 'adm');
        final db = await manager.getConnection('adm');
        await db.unprepared('drop table if exists ${_tables.join(', ')}');
        await db.unprepared('''
          create table ns_processo (id serial primary key, ano int not null,
            codigo int not null, assunto text, situacao varchar(20),
            unique (ano, codigo));
          create table ns_andamento (processo_id int not null, seq int not null,
            descricao text, primary key (processo_id, seq));
          create table ns_auditoria (id serial primary key, processo_id int,
            descricao text);
          create table ns_contador (id int primary key, total int not null);
          insert into ns_contador values (1, 0);
          create table ns_tag (id serial primary key,
            slug varchar(40) not null unique, nome varchar(40));
          create table ns_pessoa (id serial primary key, nome varchar(60),
            versao int not null default 0);
        ''');
        final baseline = await _connections(db);

        final config = _config(driver, pool);
        final first =
            await _spawn<List>(_serverMain, (ready) => [config, 0, ready]);
        final port = first[0] as int;
        final serverCommands = <SendPort>[first[1] as SendPort];
        for (var s = 1; s < _servers; s++) {
          final started =
              await _spawn<List>(_serverMain, (ready) => [config, port, ready]);
          serverCommands.add(started[1] as SendPort);
        }

        // The peak of open connections while the clients run.
        var peak = 0;
        var sampling = true;
        final sampler = () async {
          while (sampling) {
            peak = max(peak, await _connections(db) - baseline);
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }();

        final watch = Stopwatch()..start();
        final results = await Future.wait([
          for (var c = 0; c < _clients; c++)
            _spawn<Map>(_clientMain, (reply) => [port, c, reply]),
        ]);
        watch.stop();
        sampling = false;
        await sampler;

        final unexpected = <String>[];
        for (final commands in serverCommands) {
          final stopped = ReceivePort();
          commands.send(stopped.sendPort);
          unexpected.addAll((await stopped.first as List).cast<String>());
          stopped.close();
        }

        final requests =
            results.fold<int>(0, (sum, r) => sum + (r['requests'] as int));
        final clientErrors = [
          for (final r in results) ...(r['errors'] as List).cast<String>(),
        ];
        final refused =
            results.fold<int>(0, (sum, r) => sum + (r['refused'] as int));
        print('$driver, $mode: $requests requests in ${watch.elapsed} '
            '(${(requests / watch.elapsedMilliseconds * 1000).round()}/s), '
            'peak of $peak connections'
            '${refused > 0 ? ', $refused refused (53300)' : ''}');
        expect(unexpected, isEmpty, reason: unexpected.take(5).join('\n'));
        expect(clientErrors, isEmpty, reason: clientErrors.take(5).join('\n'));

        // Every answer the clients got must match the database.
        final steps = <int, List<int>>{
          for (final r in results)
            for (final e in (r['steps'] as Map).entries)
              int.parse(e.key as String): (e.value as List).cast<int>(),
        };
        final created = steps.length;
        expect(await db.table('ns_processo').count(), created);
        expect(await db.table('ns_contador').where('id', '=', 1).value('total'),
            created,
            reason: 'counter bumped once per opening');
        final codes = await db
            .table('ns_processo')
            .where('ano', '=', _year)
            .orderBy('codigo')
            .pluck('codigo');
        expect(codes, [for (var i = 1; i <= created; i++) i],
            reason: 'codes per year without gaps or repeats');

        final seqs = await db
            .table('ns_andamento')
            .select(['processo_id', 'seq'])
            .orderBy('processo_id')
            .orderBy('seq')
            .get();
        final byProcesso = <int, List<int>>{};
        for (final row in seqs) {
          byProcesso
              .putIfAbsent(_asInt(row['processo_id']), () => [])
              .add(_asInt(row['seq']));
        }
        for (final MapEntry(key: id, value: answered) in steps.entries) {
          final stored = byProcesso[id] ?? [];
          expect(stored, [for (var i = 1; i <= answered.length + 1; i++) i],
              reason: 'steps of processo $id');
          expect([1, ...answered]..sort(), stored,
              reason: 'the numbers answered are the stored ones ($id)');
        }

        final audits =
            results.fold<int>(0, (sum, r) => sum + (r['audits'] as int));
        expect(
            await db.table('ns_auditoria').whereNotNull('processo_id').count(),
            audits,
            reason: 'audit rows kept outside the rolled back savepoints');
        expect(
            await db
                .table('ns_auditoria')
                .where('descricao', '=', 'falha')
                .count(),
            0,
            reason: 'writes before the SQL error were rolled back');

        final tags = <String, int>{};
        for (final r in results) {
          (r['tags'] as Map).forEach((slug, id) {
            final known = tags.putIfAbsent(slug as String, () => id as int);
            expect(known, id, reason: 'one id per slug across clients');
          });
        }
        expect(await db.table('ns_tag').count(), tags.length);

        final pessoas = [
          for (final r in results) ...(r['pessoas'] as List).cast<int>(),
        ];
        expect(await db.table('ns_pessoa').count(), pessoas.length);
        expect(await db.table('ns_pessoa').where('versao', '=', 99).count(), 0,
            reason: 'versao is not fillable');

        // No connection left open by the servers.
        var left = await _connections(db) - baseline;
        for (var i = 0; i < 20 && left > 0; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          left = await _connections(db) - baseline;
        }
        expect(left, 0, reason: 'connections left open after the servers');

        await db.unprepared('drop table if exists ${_tables.join(', ')}');
        await manager.getDatabaseManager().purge('adm');
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  }
}
