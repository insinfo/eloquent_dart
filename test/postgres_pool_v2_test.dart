// test/postgres_pool_v2_test.dart
import 'dart:async';
import 'dart:math';
import 'package:test/test.dart';
import 'package:eloquent/eloquent.dart';

/// Config do pool v2
const _POOL_SIZE = 4;
const _APP_NAME = 'eloquent-pgpool-v2-tests';
void main() {
  late Manager manager;
  late Connection db;

  Future<void> _bootstrap() async {
    // Schema/tabela isolados para estes testes
    await db.statement('DROP SCHEMA IF EXISTS myschema_pool CASCADE;');
    await db.statement('CREATE SCHEMA myschema_pool;');
    await db.statement('''
      CREATE TABLE myschema_pool.pool_items (
        id bigserial PRIMARY KEY,
        payload text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now()
      );
    ''');
    // seed 1 linha
    await db.table('myschema_pool.pool_items').insert({'payload': 'seed'});
  }

  setUpAll(() async {
    manager = Manager();

    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'postgres', // v2
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'schema': ['public'],
      'pool': true,
      'poolsize': _POOL_SIZE,
      'timezone': 'America/Sao_Paulo',
      'application_name': _APP_NAME,
      // timeouts curtos para o teste de timeout
      'statementTimeout': '1s',
      'lockTimeout': '1s',
      'idleInTransactionSessionTimeout': '5s',
    }, 'default');

    manager.setAsGlobal();
    db = await manager.connection('default');
    await _bootstrap();
  });

  tearDownAll(() async {
    try {
      await db.statement('DROP SCHEMA IF EXISTS myschema_pool CASCADE;');
    } catch (_) {}
    // Fecha e limpa o pool/conexões
    await manager.getDatabaseManager().purge('default');
  });

  group('Pool v2 (Postgres)', () {
    test('SELECTs concorrentes saturam o pool (uso em paralelo)', () async {
      // 2x o tamanho do pool para forçar enfileiramento
      final concurrent = max(4, _POOL_SIZE * 2); // 8
      final rnd = Random(42);
      // dorme ~0.5s em média no servidor, com pequena variação
      List<double> sleeps = List.generate(
          concurrent, (_) => (rnd.nextInt(5) + 3) / 10.0); // 0.3..0.7s
      // tempo esperado ~= ceil(n/pool) * média(sleeps)
      final avg = sleeps.reduce((a, b) => a + b) / sleeps.length;
      final waves = (concurrent / _POOL_SIZE).ceil();
      final expectedSeconds = waves * avg;

      Future<Map<String, dynamic>> one(int i, double sec) async {
        final rs = await db
            .select('select pg_sleep(?) as slept, ?::int as i', [sec, i]);
        return rs.first;
      }

      final sw = Stopwatch()..start();
      final results = await Future.wait([
        for (var i = 0; i < concurrent; i++) one(i, sleeps[i]),
      ]);
      sw.stop();

      // Sanidade: todas as linhas retornaram
      expect(results.length, concurrent);

      // O tempo total deve ser próximo de "waves * avg".
      // Damos uma margem generosa (ruído de CI/ambiente).
      final elapsed = sw.elapsedMilliseconds / 1000.0;
      // limite superior = esperado + 1.2s de folga
      expect(elapsed, lessThanOrEqualTo(expectedSeconds + 1.2),
          reason:
              'Execução muito lenta: $elapsed s (esperado ~${expectedSeconds.toStringAsFixed(2)} s)');

      // smoke check do conteúdo
      expect(results.first.containsKey('i'), isTrue);
      expect(results.first.containsKey('slept'), isTrue);
    });

    test('Transações concorrentes com rollback intencional', () async {
      // Começa contando quantas linhas existem
      final before = await db.table('myschema_pool.pool_items').count();

      final concurrent = min(6, max(2, _POOL_SIZE * 2)); // até 6
      Future<void> txTask(int i) async {
        final doRollback = i % 3 == 0; // 1/3 das transações dará rollback
        await db.transaction((txn) async {
          await txn
              .table('myschema_pool.pool_items')
              .insert({'payload': 'tx-$i-step1'});
          await txn
              .table('myschema_pool.pool_items')
              .insert({'payload': 'tx-$i-step2'});
          if (doRollback) {
            throw StateError('rollback-intencional-$i');
          }
        }).catchError((_) {
          // esperado para os casos 0, 3, ...
        });
      }

      await Future.wait([for (var i = 0; i < concurrent; i++) txTask(i)]);

      // Cada transação válida insere 2 linhas.
      final rollbacks = (concurrent / 3).floor();
      final commits = concurrent - rollbacks;
      final expectedAdded = commits * 2;

      final after = await db.table('myschema_pool.pool_items').count();
      expect(after, before + expectedAdded);
    });

    test('statementTimeout gera erro em query lenta', () async {
      // timeouts configurados em 1s; pg_sleep(2) deve exceder
      Future<void> slow() async {
        await db.select('select pg_sleep(?) as x', [2.0]);
      }

      // Aceitamos qualquer Exception aqui (o wrapper pode variar)
      await expectLater(slow(), throwsA(isA<Exception>()));
    });

    test('purge fecha o pool e permite reconexão limpa', () async {
      // Purge encerra e remove do cache
      await manager.getDatabaseManager().purge('default');

      // Reabre e REBIND na variável global para os próximos testes
      db = await manager.connection('default');

      final r = await db.select('select 1 as one');
      expect(r, isNotEmpty);
      expect(r.first['one'], anyOf(1, 1.0)); // inteiro/numérico
    });
  });

  group('Pool v2 (Postgres) — extras', () {
    test('reaproveita conexões: número de PIDs únicos <= poolsize', () async {
      // dispara mais requisições que o tamanho do pool
      final concurrent = 16;
      Future<int> one() async {
        final rs = await db.select('select pg_backend_pid() as pid');
        return (rs.first['pid'] as num).toInt();
      }

      final pids =
          await Future.wait([for (var i = 0; i < concurrent; i++) one()]);
      final unique = pids.toSet();
      expect(unique.length, lessThanOrEqualTo(_POOL_SIZE),
          reason:
              'esperado <= $_POOL_SIZE conexões simultâneas; obtivemos ${unique.length}');
    });

    test('SET LOCAL statement_timeout afeta apenas a transação atual',
        () async {
      // fora de transação: pg_sleep(0.7) passa porque conn tem 1s de timeout
      final ok = await db.select('select pg_sleep(0.7) as ok');
      expect(ok, isNotEmpty);

      // dentro da transação: força timeout menor (200ms)
      await expectLater(() async {
        await db.transaction((tx) async {
          await tx.statement("SET LOCAL statement_timeout = '200ms'");
          // deve estourar timeout local (200ms) mesmo que a conn tenha 1s
          await tx.select('select pg_sleep(0.5) as slow');
        });
      }, throwsA(isA<Exception>()));

      // e a conexão continua utilizável depois
      final after = await db.select('select 1 as one');
      expect(after.first['one'], anyOf(1, 1.0));
    });

    test('application_name e timezone propagados', () async {
      final app =
          await db.select("select current_setting('application_name') as app");
      expect((app.first['app'] as String), equals(_APP_NAME));

      final tz = await db.select("show timezone");
      // alguns PG retornam 'America/Sao_Paulo', outros normalizam; fazemos contains
      expect((tz.first['TimeZone'] ?? tz.first['timezone']).toString(),
          contains('America/Sao_Paulo'));
    });

    test('lock_timeout: update concorrente bloqueado estoura tempo', () async {
      // tabela UNLOGGED e única (evita interferência entre execuções)
      final lockTable =
          'myschema_pool.t_lock_${DateTime.now().microsecondsSinceEpoch}';
      await db.statement(
          'CREATE UNLOGGED TABLE $lockTable (id int primary key, v int)');
      await db.table(lockTable).insert({'id': 1, 'v': 0});

      // tx1: pega lock e segura sem commit
      final ready = Completer<void>();
      final hold = Completer<void>();
      final f1 = () async {
        await db.transaction((t1) async {
          await t1.table(lockTable).where('id', '=', 1).update({'v': 1});
          ready.complete(); // sinaliza que o lock está segurando
          await hold.future; // segura o lock até liberarmos
        });
      }();

      // tx2: tenta atualizar e deve bater lock_timeout=1s (config do pool)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await expectLater(() async {
        await ready.future;
        await db.table(lockTable).where('id', '=', 1).update({'v': 2});
      }, throwsA(isA<Exception>()));

      // libera o lock da tx1 e espera terminar
      hold.complete();
      await f1;

      // segue operando
      final row = await db.table(lockTable).where('id', '=', 1).first();
      expect(row, isNotNull);

      // limpeza
      await db.statement('DROP TABLE IF EXISTS $lockTable');
    });
    test('extras: GUCs padrão aplicados na sessão', () async {
      final rows = await db.select('''
    select
      current_setting('statement_timeout') as st,
      current_setting('lock_timeout') as lt,
      current_setting('idle_in_transaction_session_timeout') as it
  ''');
      final r = rows.first;
      expect((r['st'] as String).toLowerCase(), contains('1s'));
      expect((r['lt'] as String).toLowerCase(), contains('1s'));
      expect((r['it'] as String).toLowerCase(), contains('5s'));
    });
    test('extras: purge troca os PIDs (novas conexões)', () async {
      Future<int> pid() async =>
          (await db.select('select pg_backend_pid() as pid')).first['pid']
              as int;

      final before = <int>{};
      for (var i = 0; i < _POOL_SIZE; i++) before.add(await pid());

      await manager.getDatabaseManager().purge('default');
      // reabre e REBIND para que os próximos testes usem o pool válido
      db = await manager.connection('default');

      final after = <int>{};
      for (var i = 0; i < _POOL_SIZE; i++) {
        final r = await db.select('select pg_backend_pid() as pid');
        after.add(r.first['pid'] as int);
      }

      // Em geral, os conjuntos devem ser disjuntos
      expect(before.intersection(after).isEmpty, isTrue);
    });

    test('extras: SET LOCAL não vaza para fora da transação', () async {
      // dentro da TX: 200ms -> deve estourar
      await expectLater(() async {
        await db.transaction((tx) async {
          await tx.statement("SET LOCAL statement_timeout = '200ms'");
          await tx.select('select pg_sleep(0.5)'); // timeout
        });
      }, throwsA(isA<Exception>()));

      // fora da TX: volta aos 1s padrão do pool
      final ok = await db.select('select pg_sleep(0.7) as ok');
      expect(ok, isNotEmpty);
    });

    test(
        'extras: concorrência efetiva nunca excede _POOL_SIZE (medido no servidor)',
        () async {
      // lança mais requisições do que o pool comporta
      final total = _POOL_SIZE * 3;

      // dispara sleepers que ocupam a conexão por ~300ms
      var done = 0;
      final sleepers = List<Future<void>>.generate(total, (_) async {
        try {
          await db.select('select pg_sleep(0.3) as z');
        } finally {
          done++; // marca conclusão deste sleeper
        }
      });

      // amostra, em paralelo, o número de backends ATIVOS do app
      int maxActive = 0;
      final stopAt = DateTime.now().add(Duration(seconds: 2));
      while (DateTime.now().isBefore(stopAt)) {
        final rows = await db.select('''
      select count(*) as c
      from pg_stat_activity
      where application_name = ?
        and state = 'active'
        and query ilike '%select pg_sleep(0.3)%'
    ''', [_APP_NAME]);

        final c = (rows.first['c'] as num).toInt();
        if (c > maxActive) maxActive = c;

        // amostra rápido o suficiente pra capturar o pico
        await Future.delayed(Duration(milliseconds: 20));

        // sai cedo se todos os sleepers já terminaram
        if (done == total) break;
      }

      await Future.wait(sleepers);

      expect(
        maxActive,
        lessThanOrEqualTo(_POOL_SIZE),
        reason:
            'Pico medido no servidor foi $maxActive, maior que o pool=$_POOL_SIZE',
      );
    });

    //
  });
}
