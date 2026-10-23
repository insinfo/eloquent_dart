part of 'active_record.dart';

/// A query that returns models of [T]. It has the where methods of
/// [QueryBuilder2]; [configure] reaches the underlying builder (joins,
/// grouping, ...).
///
/// ```dart
/// final users = await User.definition
///     .query(db)
///     .where('ativo', true)
///     .withRelation(User.latestOrder)
///     .orderBy('nome')
///     .get();
/// ```
final class ModelQuery<T extends Model<T>> with WhereConditions<ModelQuery<T>> {
  ModelQuery._(this.connection, this.definition, this._base);

  final Connection connection;
  final ModelDefinition<T> definition;
  final QueryBuilder2 _base;
  final List<Relation<T, dynamic>> _relations = [];
  final Set<String> _removedScopes = {};
  bool _withoutAllScopes = false;
  _Trashed _trashed = _Trashed.exclude;

  @override
  final List<WhereClause> whereClauseList = [];

  @override
  ModelQuery<T> get whereSelf => this;

  /// Selects only [columns]. Models read this way save only what changes;
  /// the primary key must be selected to save or delete them.
  ModelQuery<T> select(List<String> columns) {
    _base.select(columns);
    return this;
  }

  ModelQuery<T> orderBy(String column,
      {SortDirection direction = SortDirection.ascending}) {
    _base.orderBy(column, direction: direction);
    return this;
  }

  ModelQuery<T> orderByDescending(String column) {
    _base.orderByDescending(column);
    return this;
  }

  ModelQuery<T> limit(int count) {
    _base.limit(count);
    return this;
  }

  ModelQuery<T> offset(int count) {
    _base.offset(count);
    return this;
  }

  ModelQuery<T> forPage(int page, int perPage) {
    _base.forPage(page, perPage);
    return this;
  }

  ModelQuery<T> lockForUpdate(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    _base.lockForUpdate(skipLocked: skipLocked, noWait: noWait, of: of);
    return this;
  }

  ModelQuery<T> sharedLock(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    _base.sharedLock(skipLocked: skipLocked, noWait: noWait, of: of);
    return this;
  }

  /// Changes the underlying [QueryBuilder2] (joins, grouping, CTEs, ...).
  /// Select `table.*` when joining, so the rows are still this model's.
  ModelQuery<T> configure(void Function(QueryBuilder2 query) apply) {
    apply(_base);
    return this;
  }

  /// Applies a local scope, a function that adds conditions:
  /// `static void ativos(ModelQuery<User> q) => q.where('ativo', true);`
  /// then `User.definition.query(db).apply(User.ativos)`.
  ModelQuery<T> apply(void Function(ModelQuery<T> query) scope) {
    scope(this);
    return this;
  }

  /// Leaves out the global scope [name].
  ModelQuery<T> withoutGlobalScope(String name) {
    _removedScopes.add(name);
    return this;
  }

  /// Leaves out every global scope (soft deletes are separate).
  ModelQuery<T> withoutGlobalScopes() {
    _withoutAllScopes = true;
    return this;
  }

  /// Includes soft-deleted rows.
  ModelQuery<T> withTrashed() {
    _trashed = _Trashed.include;
    return this;
  }

  /// Only soft-deleted rows.
  ModelQuery<T> onlyTrashed() {
    _trashed = _Trashed.only;
    return this;
  }

  /// Loads [relation] for every model returned, in batches (one query per
  /// relation, not one per model).
  ModelQuery<T> withRelation(Relation<T, dynamic> relation) {
    _relations.add(relation);
    return this;
  }

  /// An independent copy.
  ModelQuery<T> clone() {
    final copy = ModelQuery<T>._(connection, definition, _base.clone());
    copy.whereClauseList.addAll(whereClauseList);
    copy._relations.addAll(_relations);
    copy._removedScopes.addAll(_removedScopes);
    copy._withoutAllScopes = _withoutAllScopes;
    copy._trashed = _trashed;
    return copy;
  }

  /// The [QueryBuilder2] this query runs: global scopes, the soft-delete
  /// condition and then this query's conditions (grouped when they contain
  /// an `or`, so `a or b` cannot escape the scopes).
  QueryBuilder2 toQuery() {
    final query = _base.clone();
    var scoped = false;
    if (!_withoutAllScopes) {
      definition.globalScopes.forEach((name, scope) {
        if (_removedScopes.contains(name)) return;
        query.whereGroup(scope);
        scoped = true;
      });
    }
    if (definition.softDeletes) {
      final column = '${definition.table}.${definition.deletedAtColumn}';
      switch (_trashed) {
        case _Trashed.exclude:
          query.whereNull(column);
          scoped = true;
        case _Trashed.only:
          query.whereNotNull(column);
          scoped = true;
        case _Trashed.include:
          break;
      }
    }
    if (scoped &&
        whereClauseList.any((c) => c.connector == LogicalConnector.or)) {
      query.addWhereClause(WhereClause(LogicalConnector.and,
          GroupPredicate(List.unmodifiable(whereClauseList))));
    } else {
      for (final clause in whereClauseList) {
        query.addWhereClause(clause);
      }
    }
    return query;
  }

  String toSql() => toQuery().toSql();
  List<Object?> getBindings() => toQuery().getBindings();

  // ------------------------------------------------------------------ read

  Future<List<T>> get({Duration? timeout}) async =>
      _load(await toQuery().get(timeout: timeout));

  Future<T?> first({Duration? timeout}) async {
    final models = await _load(await toQuery().limit(1).get(timeout: timeout));
    return models.isEmpty ? null : models.first;
  }

  Future<T> firstOrFail() async =>
      await first() ??
      (throw RecordsNotFoundException('No ${definition.table} row found.'));

  /// The model with primary key [id], or `null`.
  Future<T?> find(Object id) =>
      clone().where(definition.primaryKey, id).first();

  Future<T> findOrFail(Object id) async =>
      await find(id) ??
      (throw RecordsNotFoundException(
          'No ${definition.table} with ${definition.primaryKey} = $id.'));

  Future<List<T>> findMany(Iterable<Object> ids) =>
      clone().whereIn(definition.primaryKey, ids).get();

  Future<int> count() => toQuery().count();
  Future<bool> exists() => toQuery().exists();

  /// A page of models, with the total count.
  Future<ModelPage<T>> paginate({required int page, int perPage = 15}) async {
    final result = await toQuery().paginate(page: page, perPage: perPage);
    return ModelPage<T>(
        items: await _load(result.items),
        total: result.total,
        perPage: perPage,
        currentPage: page);
  }

  /// Streams the models by keyset pagination on the primary key. Relations
  /// are not loaded here (use [get] or chunks with [withRelation]).
  Stream<T> lazyById({int chunkSize = 1000}) {
    if (_relations.isNotEmpty) {
      throw StateError('lazyById() does not load relations.');
    }
    return toQuery()
        .lazyById(chunkSize: chunkSize, column: definition.primaryKey)
        .map((row) => definition.hydrate(connection, row));
  }

  // ----------------------------------------------------------------- write

  /// Updates every matching row (without loading models); returns how many.
  Future<int> update(Map<String, Object?> values) => toQuery().update(values);

  /// Deletes every matching row (without loading models or notifying
  /// observers); with soft deletes it sets `deleted_at`. Returns how many.
  Future<int> delete() {
    if (!definition.softDeletes) return toQuery().delete();
    return toQuery()
        .update(_stamped({definition.deletedAtColumn: DateTime.now()}));
  }

  /// Removes every matching row, even with soft deletes.
  Future<int> forceDelete() => toQuery().delete();

  /// Clears `deleted_at` of the matching soft-deleted rows.
  Future<int> restore() {
    if (!definition.softDeletes) {
      throw StateError('${definition.table} does not use soft deletes.');
    }
    final query = clone();
    // Only the trashed rows (all rows would count unchanged ones too).
    if (query._trashed == _Trashed.exclude) query._trashed = _Trashed.only;
    return query.toQuery().update(_stamped({definition.deletedAtColumn: null}));
  }

  Map<String, Object?> _stamped(Map<String, Object?> values) => {
        ...values,
        if (definition.timestamps) definition.updatedAtColumn: DateTime.now(),
      };

  Future<List<T>> _load(List<Map<String, dynamic>> rows) async {
    final models = [
      for (final row in rows) definition.hydrate(connection, row)
    ];
    if (models.isNotEmpty) {
      for (final relation in _relations) {
        await relation._eagerLoad(connection, models);
      }
    }
    return models;
  }
}

enum _Trashed { exclude, include, only }

/// A page of models, from [ModelQuery.paginate].
final class ModelPage<T extends Model<T>> {
  const ModelPage(
      {required this.items,
      required this.total,
      required this.perPage,
      required this.currentPage});

  final List<T> items;
  final int total;
  final int perPage;
  final int currentPage;

  int get lastPage => total == 0 ? 1 : (total + perPage - 1) ~/ perPage;
  bool get hasMorePages => currentPage < lastPage;

  /// Laravel's JSON shape, with every model as [Model.toJson].
  Map<String, dynamic> toMap() => {
        'data': [for (final model in items) model.toJson()],
        'total': total,
        'per_page': perPage,
        'current_page': currentPage,
        'last_page': lastPage,
      };
}
