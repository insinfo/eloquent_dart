// Active Record models: no code generation and no reflection, so it works
// with AOT and Flutter. Relations, eager loading, casts, scopes, soft deletes
// and observers.
//
//   dart run bin/active_record.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

enum OrderStatus { paid, pending }

class User extends Model {
  User(super.state);

  static final definition = ModelDefinition<User>(
    table: 'ex_users',
    create: User.new, // the constructor replaces reflection
    timestamps: true, // created_at / updated_at
    softDeletes: true, // deleted_at
    casts: {'active': Casts.boolean},
  );

  static final orders = HasMany<User, Order>('orders', () => Order.definition,
      foreignKey: 'user_id');

  static final latestOrder = HasOne<User, Order>(
          'latestOrder', () => Order.definition,
          foreignKey: 'user_id')
      .latestOfMany();

  static final largestOrder = HasOne<User, Order>(
          'largestOrder', () => Order.definition,
          foreignKey: 'user_id')
      .ofMany('price', AggregateFunction.maximum);

  static final roles = BelongsToMany<User, Role>('roles', () => Role.definition,
      pivotTable: 'ex_user_role',
      foreignPivotKey: 'user_id',
      relatedPivotKey: 'role_id',
      pivotColumns: ['level']);

  /// A local scope.
  static void active(ModelQuery<User> q) => q.where('active', true);

  int get id => readAttribute<int>('id');
  String get name => readAttribute<String>('name');
  set name(String value) => writeAttribute('name', value);
  bool get isActive => readAttribute<bool>('active');
}

class Order extends Model {
  Order(super.state);

  static final definition = ModelDefinition<Order>(
    table: 'ex_orders',
    create: Order.new,
    casts: {
      'price': Casts.decimal, // PostgreSQL numeric comes as text
      'status': Casts.enumByName(OrderStatus.values),
    },
  );

  static final user = BelongsTo<Order, User>('user', () => User.definition,
      foreignKey: 'user_id');

  double? get price => readAttribute<double?>('price');
  OrderStatus get status => readAttribute<OrderStatus>('status');
}

class Role extends Model {
  Role(super.state);

  static final definition =
      ModelDefinition<Role>(table: 'ex_roles', create: Role.new);

  String get name => readAttribute<String>('name');
}

/// Receives the model's events; an exception in a `...ing` callback stops
/// the operation.
class UserObserver extends ModelObserver<User> {
  @override
  void creating(User model) {
    model.name = model.name.trim();
  }

  @override
  void created(User model) => print('observer: created ${model.name}');
}

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await _createTables(db);

  User.definition.observe(UserObserver());

  // Create: insert, then id and defaults are read back
  final ana = User.definition.make(db, {'name': '  Ana '});
  await ana.save();
  final bia = User.definition.make(db, {'name': 'Bia', 'active': false});
  await bia.save();
  print('ana: ${ana.toMap()}');

  for (final (userId, price, status) in [
    (ana.id, 120.5, 'paid'),
    (ana.id, 80.0, 'pending'),
    (bia.id, 300.0, 'paid'),
  ]) {
    await Order.definition.make(db, {
      'user_id': userId,
      'price': price,
      'status': status,
    }).save();
  }

  // Update: only the changed columns are written
  final found = await User.definition.query(db).findOrFail(ana.id);
  found.name = 'Ana Paula';
  await found.save();

  // Relations, one at a time or eager loaded for many models
  final latest = await User.latestOrder.fetch(found);
  print('latest order of ${found.name}: ${latest?.price}');

  final users = await User.definition
      .query(db)
      .withRelation(User.orders)
      .withRelation(User.largestOrder)
      .orderBy('id')
      .get();
  for (final u in users) {
    final orders = User.orders.getLoaded(u);
    final largest = User.largestOrder.getLoaded(u);
    print('${u.name}: ${orders.length} orders, largest ${largest?.price} '
        '(${largest?.status.name})');
  }

  final order = await Order.definition.query(db).where('price', 300).first();
  print('order 300 belongs to ${(await Order.user.fetch(order!))?.name}');

  // Many-to-many with pivot columns
  await Role.definition.make(db, {'id': 1, 'name': 'admin'}).save();
  await Role.definition.make(db, {'id': 2, 'name': 'editor'}).save();
  await User.roles.attach(found, [1, 2], pivot: {'level': 5});
  final sync = await User.roles.sync(found, [2]);
  final roles = await User.roles.fetch(found);
  print('sync: $sync, roles: ${roles.map((r) => r.name)}, '
      'level: ${User.roles.pivot(roles.first)['level']}');

  // Scopes, counts and pagination
  final activeCount =
      await User.definition.query(db).apply(User.active).count();
  final page = await User.definition.query(db).orderBy('id').paginate(
        page: 1,
        perPage: 10,
      );
  print('active: $activeCount, page: ${page.toMap()['total']} users');

  // Soft delete: hidden from queries until restored
  await bia.delete();
  print('after delete: ${await User.definition.query(db).count()} users, '
      '${await User.definition.query(db).onlyTrashed().count()} trashed');
  await bia.restore();
  await bia.forceDelete();

  // Inside a transaction, use ctx (or save(using: ctx))
  await db.transaction((ctx) async {
    await User.definition.make(ctx, {'name': 'Caio'}).save();
  });

  await _dropTables(db);
  await db.disconnect();
}

Future<void> _createTables(Connection db) async {
  await _dropTables(db);
  await db.unprepared('''
    create table ex_users (id serial primary key, name varchar(40),
      active boolean default true, created_at timestamp null,
      updated_at timestamp null, deleted_at timestamp null);
    create table ex_orders (id serial primary key, user_id int,
      price numeric(10,2), status varchar(10));
    create table ex_roles (id int primary key, name varchar(20));
    create table ex_user_role (user_id int, role_id int, level int);
  ''');
}

Future<void> _dropTables(Connection db) => db.unprepared(
    'drop table if exists ex_users, ex_orders, ex_roles, ex_user_role');
