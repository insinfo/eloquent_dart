// The Laravel-style QueryBuilder (`db.table()`): joins, subqueries,
// aggregates, conditional clauses, pagination and upserts.
//
//   dart run bin/query_builder.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await _createTables(db);

  // Joins
  final withClient = await db
      .table('ex_orders as o')
      .select(['o.id', 'c.name', 'o.total'])
      .join('ex_clients as c', 'c.id', '=', 'o.client_id')
      .where('o.total', '>', 100)
      .orderBy('o.id')
      .get();
  print('orders over 100: $withClient');

  // Aggregates and grouping
  final perClient = await db
      .table('ex_orders')
      .selectRaw('client_id, count(*) as orders, sum(total) as amount')
      .groupBy('client_id')
      .havingRaw('count(*) > ?', [1])
      .orderBy('client_id')
      .get();
  print('clients with more than one order: $perClient');
  print('max total: ${await db.table('ex_orders').max('total')}');

  // Subqueries: joinSub and whereExists
  final totals = db
      .table('ex_orders')
      .selectRaw('client_id, sum(total) as amount')
      .groupBy('client_id');
  final ranking = await db
      .table('ex_clients as c')
      .select(['c.name', 't.amount'])
      .joinSub(totals, 't', (JoinClause join) {
        join.on('t.client_id', '=', 'c.id');
      })
      .orderBy('t.amount', 'desc')
      .get();
  print('ranking: $ranking');

  final withOrders =
      await db.table('ex_clients as c').whereExists((QueryBuilder q) {
    q
        .selectRaw('1')
        .from('ex_orders as o')
        .whereColumn('o.client_id', '=', 'c.id');
  }).pluck('name');
  print('clients with orders: $withOrders');

  // whereIn, whereBetween, whereNull, nested groups
  final filtered = await db
      .table('ex_orders')
      .whereIn('status', ['paid', 'shipped']).whereBetween(
          'total', [50, 500]).where((QueryBuilder q) {
    q.whereNull('note').orWhere('note', '<>', 'test');
  }).count();
  print('filtered count: $filtered');

  // Clauses added only when a filter is present
  String? status = 'paid';
  String? search;
  final query = db
      .table('ex_orders')
      .when(status, (QueryBuilder q, s) => q.where('status', '=', s))
      .when(search, (QueryBuilder q, s) => q.where('note', 'ilike', '%$s%'));
  // The SQL with the bindings inlined, for logs (never execute it).
  print('raw sql: ${query.toRawSql()}');

  // ilike search over several columns; '%' and '_' in the term are escaped
  // and a blank term adds nothing. `unaccent: true` also ignores accents
  // (needs the PostgreSQL unaccent extension).
  final found = await db
      .table('ex_clients')
      .whereSearch(['name', 'email'], 'jo').pluck('name');
  print('search "jo": $found');

  // Offset pagination (count + page) and keyset pagination (no count)
  final page = await db.table('ex_orders').orderBy('id').paginate(
        perPage: 3,
        page: 2,
      );
  print('page ${page.currentPage()}/${page.lastPage()} '
      'of ${page.total()}: ${page.items()}');

  final first = await db.table('ex_orders').orderBy('id').cursorPaginate(
        perPage: 4,
      );
  final next = await db.table('ex_orders').orderBy('id').cursorPaginate(
        perPage: 4,
        cursor: first.nextCursor,
      );
  print('keyset pages: ${first.items.length} + ${next.items.length} rows');

  // UPSERT: insert, or update when the unique key exists
  await db.table('ex_clients').upsert(
    [
      {'email': 'ana@example.com', 'name': 'Ana Paula'},
      {'email': 'new@example.com', 'name': 'New client'},
    ],
    ['email'], // conflict target; the other columns are updated
  );
  final names = await db.table('ex_clients').orderBy('id').pluck('name');
  print('after upsert: $names');

  // INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING (PostgreSQL)
  final counter = await db.table('ex_counters').onConflict(['year']).doUpdate({
    'last': db.raw('ex_counters.last + 1')
  }).returning(['last']).insert({'year': 2026, 'last': 1});
  print('counter: ${counter.first['last']}');

  // Increment and decrement
  await db.table('ex_orders').where('id', '=', 1).increment('total', 10);

  // Row-by-row without loading everything: chunk pages with LIMIT/OFFSET.
  await db.table('ex_orders').orderBy('id').chunk(5, (rows, page) {
    print('chunk $page: ${rows.length} rows');
    return true; // false stops
  });

  await _dropTables(db);
  await db.disconnect();
}

Future<void> _createTables(Connection db) async {
  final schema = db.getSchemaBuilder();
  await _dropTables(db);
  await schema.create('ex_clients', (Blueprint t) {
    t.increments('id');
    t.string('name', 80);
    t.string('email', 120);
    t.unique('email');
  });
  await schema.create('ex_orders', (Blueprint t) {
    t.increments('id');
    t.integer('client_id');
    t.decimal('total', 10, 2);
    t.string('status', 20);
    t.string('note');
    t.nullable();
  });
  await schema.create('ex_counters', (Blueprint t) {
    t.integer('year');
    t.primary('year');
    t.integer('last');
  });

  final clients = ['Ana', 'João', 'Márcia'];
  for (var i = 0; i < clients.length; i++) {
    await db.table('ex_clients').insert({
      'name': clients[i],
      'email': '${clients[i].toLowerCase().replaceAll('ã', 'a')}@example.com',
    });
  }
  const statuses = ['paid', 'shipped', 'open'];
  for (var i = 1; i <= 10; i++) {
    await db.table('ex_orders').insert({
      'client_id': i % 2 + 1,
      'total': i * 40,
      'status': statuses[i % 3],
      'note': i == 4 ? 'test' : null,
    });
  }
}

Future<void> _dropTables(Connection db) async {
  final schema = db.getSchemaBuilder();
  await schema.dropIfExists('ex_orders');
  await schema.dropIfExists('ex_clients');
  await schema.dropIfExists('ex_counters');
}
