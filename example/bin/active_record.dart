// Active Record models, no code generation and no reflection, so it works
// with AOT and Flutter. User and Order have plain Dart fields and implement
// modelDefinition, toMap() and fill(); Role is an AttributeModel (columns in
// a map, typed getters/setters). Relations, eager loading, casts, mass
// assignment, hidden columns, scopes, soft deletes and observers.
//
//   dart run bin/active_record.dart
import 'dart:convert';

import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

enum OrderStatus { paid, pending }

class User extends Model<User> {
  static final definition = ModelDefinition<User>(
    table: 'ex_users',
    create: User.new, // the constructor replaces PHP's `new static`
    timestamps: true, // created_at / updated_at
    softDeletes: true, // deleted_at
    casts: {'active': Casts.boolean},
    fillable: ['name', 'email'], // what assign() may set
    hidden: ['password'], // left out of toJson()
  );

  @override
  ModelDefinition<User> get modelDefinition => definition;

  /// Laravel's `User::query()`: Dart statics are not inherited, so each
  /// model declares it (or uses `User.definition.query(db)`).
  static ModelQuery<User> query(Connection db) => definition.query(db);

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

  /// A local scope (a static: its name cannot be a field's name).
  static void onlyActive(ModelQuery<User> q) => q.where('active', true);

  int? id;
  String name = '';
  String? email;
  String? password;
  bool? active; // null on insert: the column default (true) is used
  DateTime? createdAt;
  DateTime? updatedAt;
  DateTime? deletedAt;

  @override
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'active': active,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  @override
  void fill(Map<String, dynamic> row) {
    id = row['id'] as int?;
    name = row['name'] as String;
    email = row['email'] as String?;
    password = row['password'] as String?;
    active = row['active'] as bool?;
    createdAt = row['created_at'] as DateTime?;
    updatedAt = row['updated_at'] as DateTime?;
    deletedAt = row['deleted_at'] as DateTime?;
  }
}

class Order extends Model<Order> {
  static final definition = ModelDefinition<Order>(
    table: 'ex_orders',
    create: Order.new,
    casts: {
      'price': Casts.decimal, // PostgreSQL numeric comes as text
      'status': Casts.enumByName(OrderStatus.values),
    },
  );

  @override
  ModelDefinition<Order> get modelDefinition => definition;

  static final user = BelongsTo<Order, User>('user', () => User.definition,
      foreignKey: 'user_id');

  int? id;
  int? userId;
  double? price;
  OrderStatus status = OrderStatus.pending;

  @override
  Map<String, dynamic> toMap() =>
      {'id': id, 'user_id': userId, 'price': price, 'status': status};

  @override
  void fill(Map<String, dynamic> row) {
    id = row['id'] as int?;
    userId = row['user_id'] as int?;
    price = row['price'] as double?;
    status = row['status'] as OrderStatus;
  }
}

/// The other style: the columns live in a map (Laravel's `$attributes`) and
/// the model declares typed getters and setters instead of fields and
/// toMap()/fill().
class Role extends AttributeModel<Role> {
  static final definition =
      ModelDefinition<Role>(table: 'ex_roles', create: Role.new);

  @override
  ModelDefinition<Role> get modelDefinition => definition;

  int? get id => getAttribute<int?>('id');
  set id(int? value) => setAttribute('id', value);
  String get name => getAttribute<String>('name');
  set name(String value) => setAttribute('name', value);
}

/// Scopes can also be extensions: `User.query(db).withEmail()`.
extension UserScopes on ModelQuery<User> {
  ModelQuery<User> withEmail() => whereNotNull('email');
}

/// Receives the model's events; an exception in a `...ing` callback stops
/// the operation, and a callback may change fields before they are written.
class UserObserver extends ModelObserver<User> {
  @override
  void creating(User model) => model.name = model.name.trim();

  @override
  void created(User model) => print('observer: created ${model.name}');
}

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await _createTables(db);

  User.definition.observe(UserObserver());

  // Create with the constructor; id and column defaults are read back
  final ana = User()
    ..name = '  Ana '
    ..email = 'ana@example.com'
    ..password = 'secret';
  await ana.save(using: db);
  print('ana: id ${ana.id}, active ${ana.active}');

  // Mass assignment from request input: only the fillable columns
  final bia = User.definition.make(db)
    ..assign({'name': 'Bia', 'email': 'bia@example.com', 'id': 999});
  await bia.save();
  print('bia: id ${bia.id} (the 999 was ignored)');

  // toJson() leaves out the hidden columns; jsonEncode works on a model
  print('json: ${jsonEncode(ana)}');

  for (final (userId, price, status) in [
    (ana.id, 120.5, OrderStatus.paid),
    (ana.id, 80.0, OrderStatus.pending),
    (bia.id, 300.0, OrderStatus.paid),
  ]) {
    await (Order()
          ..userId = userId
          ..price = price
          ..status = status)
        .save(using: db);
  }

  // Update: only the changed columns are written
  final found = await User.query(db).findOrFail(ana.id!);
  found.name = 'Ana Paula';
  print('dirty: ${found.getDirty().keys}');
  await found.save();

  // Relations, one at a time or eager loaded for many models
  final latest = await User.latestOrder.fetch(found);
  print('latest order of ${found.name}: ${latest?.price}');

  final users = await User.query(db)
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
  for (final (id, name) in [(1, 'admin'), (2, 'editor')]) {
    await (Role()
          ..id = id
          ..name = name)
        .save(using: db);
  }
  await User.roles.attach(found, [1, 2], pivot: {'level': 5});
  final sync = await User.roles.sync(found, [2]);
  final roles = await User.roles.fetch(found);
  print('sync: $sync, roles: ${roles.map((r) => r.name)}, '
      'level: ${User.roles.pivot(roles.first)['level']}');

  // Scopes, counts and pagination (toMap() of a page uses toJson())
  final activeCount = await User.query(db).apply(User.onlyActive).count();
  final withEmail = await User.query(db).withEmail().count();
  final page = await User.query(db).orderBy('id').paginate(page: 1);
  print('active: $activeCount, with e-mail: $withEmail, '
      'page: ${page.toMap()['total']} users');

  // Soft delete: hidden from queries until restored
  await bia.delete();
  final remaining = await User.query(db).count();
  final trashed = await User.query(db).onlyTrashed().count();
  print('after delete: $remaining users, $trashed trashed '
      '(deleted_at ${bia.deletedAt})');
  await bia.restore();
  await bia.forceDelete();

  // Inside a transaction, use ctx (or save(using: ctx))
  await db.transaction((ctx) async {
    await (User()..name = 'Caio').save(using: ctx);
  });

  await _dropTables(db);
  await db.disconnect();
}

Future<void> _createTables(Connection db) async {
  await _dropTables(db);
  await db.unprepared('''
    create table ex_users (id serial primary key, name varchar(40),
      email varchar(80), password varchar(80),
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
