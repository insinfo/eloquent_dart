// benchmark/query_compile_benchmark.dart
//
// Micro-benchmark for the query-builder compilation hot path (toSql()).
// No database connection is used — it only measures SQL string generation.
//
//   dart run benchmark/query_compile_benchmark.dart
//   dart compile exe benchmark/query_compile_benchmark.dart && ./query_compile_benchmark.exe

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';

QueryBuilder _newBuilder() =>
    QueryBuilder(_NoopConnection(), QueryPostgresGrammar(), PostgresProcessor());

/// A representative "medium complexity" query rebuilt fresh each iteration so
/// we measure builder construction + compilation, not cached state.
String _compileMedium() {
  final qb = _newBuilder()
      .from('users as u')
      .select(['u.id', 'u.name', 'u.email', 'p.title'])
      .join('profiles as p', 'p.user_id', '=', 'u.id')
      .where('u.active', '=', true)
      .where('u.age', '>=', 18)
      .whereIn('u.role', ['admin', 'staff', 'user'])
      .whereNull('u.deleted_at')
      .orderBy('u.created_at', 'desc')
      .limit(50)
      .offset(100);
  return qb.toSql();
}

void main() {
  const warmup = 20000;
  const iterations = 200000;

  // Warmup (JIT).
  var sink = 0;
  for (var i = 0; i < warmup; i++) {
    sink += _compileMedium().length;
  }

  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    sink += _compileMedium().length;
  }
  sw.stop();

  final perOp = sw.elapsedMicroseconds / iterations;
  final opsPerSec = (iterations / (sw.elapsedMicroseconds / 1e6)).round();
  print('sample SQL: ${_compileMedium()}');
  print('iterations: $iterations');
  print('total_ms:   ${sw.elapsedMilliseconds}');
  print('us_per_op:  ${perOp.toStringAsFixed(3)}');
  print('ops_per_s:  $opsPerSec');
  print('checksum:   $sink');
}

/// Minimal ConnectionInterface — the benchmark never executes queries, it only
/// compiles SQL, so these throw if accidentally invoked.
class _NoopConnection implements ConnectionInterface {
  Never _no() => throw UnsupportedError('benchmark: no execution');

  @override
  QueryBuilder table(String table) =>
      QueryBuilder(this, QueryPostgresGrammar(), PostgresProcessor())
          .from(table);

  @override
  QueryExpression raw(value) => QueryExpression(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => _no();
}
