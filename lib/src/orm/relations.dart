part of 'active_record.dart';

/// The aggregate that picks one related row in [HasOne.ofMany].
enum AggregateFunction { minimum, maximum }

/// Keys per `IN (...)` when loading relations in batches.
const _relationBatchSize = 5000;

/// Column with the rank of each row in a "one of many" batch query.
const _rankColumn = '__eloquent_rank';

/// Prefix of the pivot columns selected by [BelongsToMany].
const _pivotPrefix = '__pivot_';

/// A relation from a parent model [P] to related models [R], declared once
/// as a static field of the parent:
///
/// ```dart
/// static final orders = HasMany<User, Order>('orders', () => Order.definition,
///     foreignKey: 'user_id');
/// ```
///
/// - `relation.of(parent)` is the query of one parent's related rows;
/// - `relation.fetch(parent)` runs it and keeps the result on the parent;
/// - `ModelQuery.withRelation(relation)` loads it for many parents at once;
/// - `relation.getLoaded(parent)` reads what was loaded (it throws when the
///   relation was not loaded, which is different from "no related row").
///
/// The related definition is a function so models can refer to each other.
/// [constraints] filters the candidate rows (e.g. only paid orders).
abstract class Relation<P extends Model<P>, R extends Model<R>> {
  Relation(this.name, this._related, this.constraints);

  /// The key of the relation in [Model.toMap] and in error messages.
  final String name;
  final ModelDefinition<R> Function() _related;

  /// Conditions on the related rows, applied before any choice.
  final void Function(WhereBuilder where)? constraints;

  ModelDefinition<R> get related => _related();

  /// Whether the relation was loaded on [parent].
  bool isLoaded(P parent) => parent._state.relations.containsKey(this);

  Object? _loadedValue(P parent) {
    if (!isLoaded(parent)) {
      throw StateError('Relation "$name" was not loaded on '
          '${parent.modelDefinition.table}: use withRelation(...) or fetch(...).');
    }
    return parent._state.relations[this];
  }

  void _store(P parent, Object? value) {
    parent._state.relations[this] = value;
  }

  ModelQuery<R> _relatedQuery(Connection connection) {
    final query = related.query(connection);
    final where = constraints;
    if (where != null) query.whereGroup(where);
    return query;
  }

  Future<void> _eagerLoad(Connection connection, List<P> parents);
}

/// The distinct non-null values of [column] in [models], as found.
List<Object> _distinctKeys(Iterable<Model> models, String column) {
  final seen = <String>{};
  final keys = <Object>[];
  for (final model in models) {
    final value = model._relationKey(column);
    if (value != null && seen.add(_keyOf(value))) keys.add(value);
  }
  return keys;
}

/// Keys are compared as text: drivers may return `1`, `BigInt.one` or `'1'`.
String _keyOf(Object? value) => '$value';

Iterable<List<Object>> _chunks(List<Object> keys) sync* {
  for (var i = 0; i < keys.length; i += _relationBatchSize) {
    yield keys.sublist(
        i,
        i + _relationBatchSize > keys.length
            ? keys.length
            : i + _relationBatchSize);
  }
}

/// One related model (`orders.user_id = users.id`), optionally chosen among
/// many by [latestOfMany], [oldestOfMany] or [ofMany].
///
/// Without a choice, when several rows match, the lowest primary key wins;
/// a real one-to-one relation should have a UNIQUE foreign key.
final class HasOne<P extends Model<P>, R extends Model<R>>
    extends Relation<P, R> {
  HasOne(String name, ModelDefinition<R> Function() related,
      {required this.foreignKey,
      this.localKey = 'id',
      void Function(WhereBuilder where)? where})
      : _choice = null,
        super(name, related, where);

  HasOne._(String name, ModelDefinition<R> Function() related, this.foreignKey,
      this.localKey, void Function(WhereBuilder)? where, this._choice)
      : super(name, related, where);

  /// Column of the related table that points at the parent.
  final String foreignKey;

  /// Column of the parent that [foreignKey] references.
  final String localKey;
  final _OneOfMany? _choice;

  /// The related row with the highest [column] (default: its primary key).
  HasOne<P, R> latestOfMany([String? column]) =>
      _with(_OneOfMany(column, descending: true));

  /// The related row with the lowest [column] (default: its primary key).
  HasOne<P, R> oldestOfMany([String? column]) =>
      _with(_OneOfMany(column, descending: false));

  /// The related row with the highest (maximum) or lowest (minimum)
  /// [column]. Rows where [column] is null are not candidates; ties go to
  /// the highest primary key.
  HasOne<P, R> ofMany(String column, AggregateFunction aggregate) => _with(
      _OneOfMany(column, descending: aggregate == AggregateFunction.maximum));

  HasOne<P, R> _with(_OneOfMany choice) =>
      HasOne._(name, _related, foreignKey, localKey, constraints, choice);

  /// The query of [parent]'s related row.
  ModelQuery<R> of(P parent, {Connection? using}) {
    final query = _relatedQuery(using ?? parent.connection);
    final value = parent._relationKey(localKey);
    if (value == null) {
      query.whereIn(foreignKey, const []);
    } else {
      query.where(foreignKey, value);
    }
    final pk = related.primaryKey;
    final choice = _choice;
    if (choice == null) {
      query.orderBy(pk);
    } else {
      final column = choice.column ?? pk;
      if (column != pk) query.whereNotNull(column);
      query.orderBy(column,
          direction: choice.descending
              ? SortDirection.descending
              : SortDirection.ascending);
      if (column != pk) query.orderByDescending(pk);
    }
    return query.limit(1);
  }

  /// Reads [parent]'s related row and keeps it on [parent].
  Future<R?> fetch(P parent, {Connection? using}) async {
    final model = await of(parent, using: using).first();
    _store(parent, model);
    return model;
  }

  /// The loaded related row (`null`: there is none).
  R? getLoaded(P parent) => _loadedValue(parent) as R?;

  @override
  Future<void> _eagerLoad(Connection connection, List<P> parents) async {
    final found = <String, R>{};
    final related = this.related;
    for (final chunk in _chunks(_distinctKeys(parents, localKey))) {
      if (_choice == null) {
        final models = await _relatedQuery(connection)
            .whereIn(foreignKey, chunk)
            .orderBy(related.primaryKey)
            .get();
        for (final model in models) {
          found.putIfAbsent(_keyOf(model._value(foreignKey)), () => model);
        }
      } else {
        for (final row in await _rankedRows(connection, chunk)) {
          row.remove(_rankColumn);
          found[_keyOf(row[foreignKey])] = related.hydrate(connection, row);
        }
      }
    }
    for (final parent in parents) {
      final value = parent._relationKey(localKey);
      _store(parent, value == null ? null : found[_keyOf(value)]);
    }
  }

  /// `select * from (select t.*, row_number() over (partition by fk order by
  /// column dir, pk desc) as rank from t where fk in (...)) where rank = 1`:
  /// one row per parent.
  Future<List<Map<String, dynamic>>> _rankedRows(
      Connection connection, List<Object> keys) {
    final grammar = connection.getQueryGrammar();
    final related = this.related;
    final pk = related.primaryKey;
    final choice = _choice!;
    final column = choice.column ?? pk;
    final direction = choice.descending ? 'desc' : 'asc';
    final order = column == pk
        ? '${grammar.wrap(pk)} $direction'
        : '${grammar.wrap(column)} $direction, ${grammar.wrap(pk)} desc';
    // From the related ModelQuery, so global scopes, soft deletes and the
    // relation's constraints filter the candidates before the ranking.
    final inner = _relatedQuery(connection)
        .toQuery()
        .select(['${related.table}.*'])
        .selectRaw('row_number() over (partition by '
            '${grammar.wrap(foreignKey)} order by $order) as $_rankColumn')
        .whereIn(foreignKey, keys);
    if (column != pk) inner.whereNotNull(column);
    return QueryBuilder2(connection)
        .fromSubquery(inner, '__eloquent_ranked')
        .where(_rankColumn, 1)
        .get();
  }
}

final class _OneOfMany {
  const _OneOfMany(this.column, {required this.descending});

  final String? column;
  final bool descending;
}

/// The related models (`orders.user_id = users.id`), by primary key.
final class HasMany<P extends Model<P>, R extends Model<R>>
    extends Relation<P, R> {
  HasMany(String name, ModelDefinition<R> Function() related,
      {required this.foreignKey,
      this.localKey = 'id',
      void Function(WhereBuilder where)? where})
      : super(name, related, where);

  final String foreignKey;
  final String localKey;

  ModelQuery<R> of(P parent, {Connection? using}) {
    final query = _relatedQuery(using ?? parent.connection);
    final value = parent._relationKey(localKey);
    return value == null
        ? query.whereIn(foreignKey, const [])
        : query.where(foreignKey, value);
  }

  Future<List<R>> fetch(P parent, {Connection? using}) async {
    final models =
        await of(parent, using: using).orderBy(related.primaryKey).get();
    _store(parent, List<R>.unmodifiable(models));
    return models;
  }

  /// The loaded related models (empty: there are none).
  List<R> getLoaded(P parent) => _loadedValue(parent) as List<R>;

  @override
  Future<void> _eagerLoad(Connection connection, List<P> parents) async {
    final found = <String, List<R>>{};
    for (final chunk in _chunks(_distinctKeys(parents, localKey))) {
      final models = await _relatedQuery(connection)
          .whereIn(foreignKey, chunk)
          .orderBy(related.primaryKey)
          .get();
      for (final model in models) {
        found
            .putIfAbsent(_keyOf(model._value(foreignKey)), () => [])
            .add(model);
      }
    }
    for (final parent in parents) {
      final value = parent._relationKey(localKey);
      _store(
          parent,
          List<R>.unmodifiable(
              value == null ? const [] : found[_keyOf(value)] ?? const []));
    }
  }
}

/// The owner model (`orders.user_id` -> `users.id`).
final class BelongsTo<P extends Model<P>, R extends Model<R>>
    extends Relation<P, R> {
  BelongsTo(String name, ModelDefinition<R> Function() related,
      {required this.foreignKey,
      this.ownerKey = 'id',
      void Function(WhereBuilder where)? where})
      : super(name, related, where);

  /// Column of the parent (child row) that points at the owner.
  final String foreignKey;

  /// Column of the owner that [foreignKey] references.
  final String ownerKey;

  ModelQuery<R> of(P parent, {Connection? using}) {
    final query = _relatedQuery(using ?? parent.connection);
    final value = parent._relationKey(foreignKey);
    return value == null
        ? query.whereIn(ownerKey, const [])
        : query.where(ownerKey, value);
  }

  Future<R?> fetch(P parent, {Connection? using}) async {
    final model = await of(parent, using: using).first();
    _store(parent, model);
    return model;
  }

  R? getLoaded(P parent) => _loadedValue(parent) as R?;

  @override
  Future<void> _eagerLoad(Connection connection, List<P> parents) async {
    final found = <String, R>{};
    for (final chunk in _chunks(_distinctKeys(parents, foreignKey))) {
      final models =
          await _relatedQuery(connection).whereIn(ownerKey, chunk).get();
      for (final model in models) {
        found[_keyOf(model._value(ownerKey))] = model;
      }
    }
    for (final parent in parents) {
      final value = parent._relationKey(foreignKey);
      _store(parent, value == null ? null : found[_keyOf(value)]);
    }
  }
}

/// Many-to-many through a pivot table (`role_user.user_id`,
/// `role_user.role_id`).
///
/// ```dart
/// static final roles = BelongsToMany<User, Role>('roles', () => Role.definition,
///     pivotTable: 'role_user', foreignPivotKey: 'user_id',
///     relatedPivotKey: 'role_id', pivotColumns: ['concedido_em']);
///
/// await User.roles.attach(user, [1, 2], pivot: {'concedido_em': agora});
/// final roles = await User.roles.fetch(user);
/// User.roles.pivot(roles.first)['concedido_em'];
/// ```
///
/// Columns in [constraints] and later conditions should be qualified
/// (`roles.nome`): the query joins the pivot table.
final class BelongsToMany<P extends Model<P>, R extends Model<R>>
    extends Relation<P, R> {
  BelongsToMany(String name, ModelDefinition<R> Function() related,
      {required this.pivotTable,
      required this.foreignPivotKey,
      required this.relatedPivotKey,
      this.parentKey = 'id',
      this.relatedKey = 'id',
      this.pivotColumns = const [],
      void Function(WhereBuilder where)? where})
      : super(name, related, where);

  final String pivotTable;

  /// Pivot column that points at the parent.
  final String foreignPivotKey;

  /// Pivot column that points at the related model.
  final String relatedPivotKey;
  final String parentKey;
  final String relatedKey;

  /// Extra pivot columns read with the related models.
  final List<String> pivotColumns;

  ModelQuery<R> _pivotQuery(Connection connection) {
    final table = related.table;
    return _relatedQuery(connection).configure((query) {
      query
        ..join(pivotTable, '$pivotTable.$relatedPivotKey', '$table.$relatedKey')
        ..select([
          '$table.*',
          for (final column in {
            foreignPivotKey,
            relatedPivotKey,
            ...pivotColumns
          })
            '$pivotTable.$column as $_pivotPrefix$column',
        ]);
    });
  }

  ModelQuery<R> of(P parent, {Connection? using}) {
    final query = _pivotQuery(using ?? parent.connection);
    final value = parent._relationKey(parentKey);
    return value == null
        ? query.whereIn('$pivotTable.$foreignPivotKey', const [])
        : query.where('$pivotTable.$foreignPivotKey', value);
  }

  Future<List<R>> fetch(P parent, {Connection? using}) async {
    final models = await of(parent, using: using)
        .orderBy('${related.table}.${related.primaryKey}')
        .get();
    _store(parent, List<R>.unmodifiable(models));
    return models;
  }

  List<R> getLoaded(P parent) => _loadedValue(parent) as List<R>;

  /// The pivot values of [model], read through this relation.
  Map<String, Object?> pivot(R model) {
    final values = model._state.pivot;
    if (values == null) {
      throw StateError('$model was not read through "$name".');
    }
    return Map.unmodifiable(values);
  }

  /// Inserts pivot rows linking [parent] to [related] (ids or models).
  Future<int> attach(P parent, Iterable<Object> related,
      {Map<String, Object?> pivot = const {}, Connection? using}) async {
    final key = _parentKeyOf(parent);
    final ids = related.map(_relatedKeyOf).toList();
    parent._state.relations.remove(this);
    if (ids.isEmpty) return 0;
    return QueryBuilder2(using ?? parent.connection, pivotTable).insertMany([
      for (final id in ids)
        {foreignPivotKey: key, relatedPivotKey: id, ...pivot},
    ]);
  }

  /// Deletes the pivot rows of [parent] (only those of [related] when given).
  Future<int> detach(P parent,
      {Iterable<Object>? related, Connection? using}) async {
    final query = QueryBuilder2(using ?? parent.connection, pivotTable)
        .where(foreignPivotKey, _parentKeyOf(parent));
    parent._state.relations.remove(this);
    if (related != null) {
      final ids = related.map(_relatedKeyOf).toList();
      if (ids.isEmpty) return 0;
      query.whereIn(relatedPivotKey, ids);
    }
    return query.delete();
  }

  /// Makes [related] the exact set linked to [parent]: attaches the missing
  /// ones and detaches the others. Run it in a transaction (`using: ctx`)
  /// to make it atomic.
  Future<({List<Object> attached, List<Object> detached})> sync(
      P parent, Iterable<Object> related,
      {Map<String, Object?> pivot = const {}, Connection? using}) async {
    final connection = using ?? parent.connection;
    final wanted = {
      for (final id in related.map(_relatedKeyOf)) _keyOf(id): id,
    };
    final current = await QueryBuilder2(connection, pivotTable)
        .where(foreignPivotKey, _parentKeyOf(parent))
        .pluck<Object?>(relatedPivotKey);
    final currentKeys = {for (final id in current) _keyOf(id)};
    final detached = [
      for (final id in current)
        if (id != null && !wanted.containsKey(_keyOf(id))) id,
    ];
    final attached = [
      for (final entry in wanted.entries)
        if (!currentKeys.contains(entry.key)) entry.value,
    ];
    if (detached.isNotEmpty) {
      await detach(parent, related: detached, using: connection);
    }
    if (attached.isNotEmpty) {
      await attach(parent, attached, pivot: pivot, using: connection);
    }
    parent._state.relations.remove(this);
    return (attached: attached, detached: detached);
  }

  Object _parentKeyOf(P parent) =>
      parent._relationKey(parentKey) ??
      (throw StateError('${parent.modelDefinition.table}: "$parentKey" is null '
          '(save the model first).'));

  Object _relatedKeyOf(Object value) {
    if (value is Model) {
      return value._relationKey(relatedKey) ??
          (throw ArgumentError.value(value, 'related', 'Not saved.'));
    }
    return value;
  }

  @override
  Future<void> _eagerLoad(Connection connection, List<P> parents) async {
    final found = <String, List<R>>{};
    final related = this.related;
    for (final chunk in _chunks(_distinctKeys(parents, parentKey))) {
      final models = await _pivotQuery(connection)
          .whereIn('$pivotTable.$foreignPivotKey', chunk)
          .orderBy('${related.table}.${related.primaryKey}')
          .get();
      for (final model in models) {
        found
            .putIfAbsent(_keyOf(model._state.pivot![foreignPivotKey]), () => [])
            .add(model);
      }
    }
    for (final parent in parents) {
      final value = parent._relationKey(parentKey);
      _store(
          parent,
          List<R>.unmodifiable(
              value == null ? const [] : found[_keyOf(value)] ?? const []));
    }
  }
}
