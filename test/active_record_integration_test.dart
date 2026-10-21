// Active Record models and relations on PostgreSQL (four adapters) and
// MariaDB/MySQL. Requires localhost:5432 / 3306, database `banco_teste`,
// dart/dart.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

enum OrderStatus { pago, pendente }

class User extends Model {
  User(super.state);

  static final definition = ModelDefinition<User>(
    table: 'ar_users',
    create: User.new,
    timestamps: true,
    casts: {'ativo': Casts.boolean},
  );

  /// The last order (highest id).
  static final latestOrder = HasOne<User, Order>(
          'latestOrder', () => Order.definition,
          foreignKey: 'user_id')
      .latestOfMany();

  /// The most expensive order (ties: highest id; null prices ignored).
  static final largestOrder = HasOne<User, Order>(
          'largestOrder', () => Order.definition,
          foreignKey: 'user_id')
      .ofMany('price', AggregateFunction.maximum);

  static final orders = HasMany<User, Order>('orders', () => Order.definition,
      foreignKey: 'user_id');

  static final paidOrders = HasMany<User, Order>(
      'paidOrders', () => Order.definition,
      foreignKey: 'user_id', where: (w) => w.where('status', 'pago'));

  int get id => readAttribute<int>('id');
  String get name => readAttribute<String>('name');
  set name(String value) => writeAttribute('name', value);
  bool get ativo => readAttribute<bool>('ativo');
  set ativo(bool value) => writeAttribute('ativo', value);
}

class Order extends Model {
  Order(super.state);

  static final definition = ModelDefinition<Order>(
    table: 'ar_orders',
    create: Order.new,
    incrementing: false,
    casts: {
      'price': Casts.decimal,
      'status': Casts.enumByName(OrderStatus.values),
    },
  );

  static final user = BelongsTo<Order, User>('user', () => User.definition,
      foreignKey: 'user_id');

  int get id => readAttribute<int>('id');
  double? get price => readAttribute<double?>('price');
  OrderStatus get status => readAttribute<OrderStatus>('status');
}

Map<String, dynamic> _config(String driver) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
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
      };

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      final mysql = driver == 'mysql';
      late User ana, bia, caio;

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'ar_$driver');
        db = await manager.getConnection('ar_$driver');
        await db.execute('DROP TABLE IF EXISTS ar_orders');
        await db.execute('DROP TABLE IF EXISTS ar_users');
        await db.execute(mysql
            ? 'CREATE TABLE ar_users (id int AUTO_INCREMENT PRIMARY KEY, '
                'name varchar(40), ativo tinyint(1) DEFAULT 1, '
                'created_at datetime NULL, updated_at datetime NULL)'
            : 'CREATE TABLE ar_users (id serial PRIMARY KEY, name varchar(40), '
                'ativo boolean DEFAULT true, created_at timestamp NULL, '
                'updated_at timestamp NULL)');
        await db.execute('CREATE TABLE ar_orders (id int PRIMARY KEY, '
            'user_id int, price numeric(10,2) NULL, status varchar(10))');

        ana = User.definition.make(db, {'name': 'Ana'});
        bia = User.definition.make(db, {'name': 'Bia', 'ativo': false});
        caio = User.definition.make(db, {'name': 'Caio'});
        for (final user in [ana, bia, caio]) {
          await user.save();
        }
        await db.table2('ar_orders').insertMany([
          // Ana: 11 and 12 tie on price; 13 is the latest.
          {'id': 11, 'user_id': ana.id, 'price': 100, 'status': 'pago'},
          {'id': 12, 'user_id': ana.id, 'price': 100, 'status': 'pendente'},
          {'id': 13, 'user_id': ana.id, 'price': 90, 'status': 'pago'},
          // Bia: only null prices.
          {'id': 14, 'user_id': bia.id, 'price': null, 'status': 'pendente'},
          {'id': 15, 'user_id': bia.id, 'price': null, 'status': 'pago'},
          // Caio: no orders.
        ]);
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS ar_orders');
        await db.execute('DROP TABLE IF EXISTS ar_users');
        await manager.getDatabaseManager().purge('ar_$driver');
      });

      test('save inserts, reads back the key and the defaults', () async {
        expect(ana.exists, isTrue);
        expect([ana.id, bia.id, caio.id], [1, 2, 3]);
        if (!mysql) {
          expect(ana.ativo, isTrue, reason: 'column default read back');
        }
        final found = await User.definition.query(db).findOrFail(ana.id);
        expect(found.name, 'Ana');
        expect(found.ativo, isTrue);
        expect(found.readAttribute<DateTime?>('created_at'), isNotNull);
        expect(await User.definition.query(db).find(99), isNull);
      });

      test('a partial select saves only what changed', () async {
        final partial = (await User.definition
            .query(db)
            .select(['id', 'name'])
            .where('id', bia.id)
            .first())!;
        expect(() => partial.ativo, throwsStateError,
            reason: 'not selected is not null');
        partial.name = 'Beatriz';
        expect(partial.getDirty().keys, ['name']);
        await partial.save();

        final again = (await User.definition.query(db).find(bia.id))!;
        expect(again.name, 'Beatriz');
        expect(again.ativo, isFalse, reason: 'untouched column kept');
        expect(again.isDirty(), isFalse);
        await again.save(); // nothing to write
      });

      test('latestOfMany and ofMany for one user', () async {
        expect((await User.latestOrder.fetch(ana))!.id, 13);
        expect((await User.largestOrder.fetch(ana))!.id, 12,
            reason: 'tie on 100 goes to the highest id');
        expect((await User.latestOrder.fetch(bia))!.id, 15);
        expect(await User.largestOrder.fetch(bia), isNull,
            reason: 'only null prices');
        expect(await User.latestOrder.fetch(caio), isNull);
        expect(User.largestOrder.getLoaded(ana)!.price, 100);
      });

      test('eager loading: one query per relation', () async {
        final sql = <String>[];
        final stop = db.listen((q) => sql.add(q.sql));
        final users = await User.definition
            .query(db)
            .withRelation(User.latestOrder)
            .withRelation(User.largestOrder)
            .withRelation(User.orders)
            .withRelation(User.paidOrders)
            .orderBy('id')
            .get();
        stop();
        expect(sql, hasLength(5), reason: 'users + 4 relations');

        final [a, b, c] = users;
        expect(User.latestOrder.getLoaded(a)!.id, 13);
        expect(User.largestOrder.getLoaded(a)!.id, 12);
        expect(User.latestOrder.getLoaded(b)!.id, 15);
        expect(User.largestOrder.getLoaded(b), isNull);
        expect(User.latestOrder.getLoaded(c), isNull);
        expect(User.largestOrder.getLoaded(c), isNull);
        expect(User.orders.getLoaded(a).map((o) => o.id), [11, 12, 13]);
        expect(User.orders.getLoaded(c), isEmpty);
        expect(User.paidOrders.getLoaded(a).map((o) => o.id), [11, 13]);
        expect(User.paidOrders.getLoaded(a).first.status, OrderStatus.pago);

        final map = a.toMap();
        expect((map['latestOrder'] as Map)['id'], 13);
        expect((map['orders'] as List), hasLength(3));
      });

      test('a relation that was not loaded throws', () async {
        final user = (await User.definition.query(db).find(ana.id))!;
        expect(() => User.latestOrder.getLoaded(user), throwsStateError);
        expect(User.latestOrder.isLoaded(user), isFalse);
      });

      test('belongsTo, filters and pagination', () async {
        final orders = await Order.definition
            .query(db)
            .whereIn('status', ['pago'])
            .withRelation(Order.user)
            .orderBy('id')
            .get();
        expect(orders.map((o) => Order.user.getLoaded(o)!.name),
            ['Ana', 'Ana', 'Bia']);

        final page = await Order.definition
            .query(db)
            .orderBy('id')
            .withRelation(Order.user)
            .paginate(page: 2, perPage: 2);
        expect(page.total, 5);
        expect(page.items.map((o) => o.id), [13, 14]);
        expect((page.toMap()['data'] as List).first['user']['name'], 'Ana');
      });

      test('delete, refresh, transaction', () async {
        await caio.delete();
        expect(caio.exists, isFalse);
        expect(await User.definition.query(db).count(), 2);

        bia.name = 'Outro';
        await bia.refresh();
        expect(bia.name, 'Bia');

        await expectLater(db.transaction((ctx) async {
          final novo = User.definition.make(ctx, {'name': 'Temp'});
          await novo.save();
          throw StateError('rollback');
        }), throwsStateError);
        expect(await User.definition.query(db).where('name', 'Temp').exists(),
            isFalse);
      });
    });
  }
}
