/// Active Record models without code generation or reflection: a model has
/// plain Dart fields, maps them to columns with [Model.toMap] and
/// [Model.fill], and points at its [ModelDefinition] (table, constructor,
/// casts, fillable, hidden); relations are declared once as static fields
/// ([HasOne], [HasMany], [BelongsTo], [BelongsToMany]) and loaded per model
/// or in batches.
///
/// The Data Mapper option ([Repository] and [EntityMapper]) stays available
/// for classes that do not extend [Model].
library;

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:eloquent/eloquent.dart';

part 'casts.dart';
part 'model_query.dart';
part 'relations.dart';

/// Creates an empty model: the model's constructor, e.g. `Post.new`. It is
/// what PHP's `new static` does in Laravel, without reflection.
typedef ModelFactory<T extends Model<T>> = T Function();

/// Table, key, constructor, casts and mass-assignment rules of a model.
///
/// ```dart
/// class Post extends Model<Post> {
///   static final definition = ModelDefinition<Post>(
///     table: 'posts',
///     create: Post.new,
///     fillable: ['title', 'body'],
///     hidden: ['secret'],
///   );
///
///   @override
///   ModelDefinition<Post> get modelDefinition => definition;
///
///   int? id;
///   String title = '';
///   String? body;
///   String? secret;
///
///   @override
///   Map<String, dynamic> toMap() =>
///       {'id': id, 'title': title, 'body': body, 'secret': secret};
///
///   @override
///   void fill(Map<String, dynamic> row) {
///     id = row['id'] as int?;
///     title = row['title'] as String;
///     body = row['body'] as String?;
///     secret = row['secret'] as String?;
///   }
/// }
/// ```
final class ModelDefinition<T extends Model<T>> {
  ModelDefinition({
    required this.table,
    required this.create,
    this.primaryKey = 'id',
    this.incrementing = true,
    Map<String, AttributeCast<Object?>> casts = const {},
    List<String> fillable = const [],
    List<String> hidden = const [],
    this.timestamps = false,
    this.createdAtColumn = 'created_at',
    this.updatedAtColumn = 'updated_at',
    this.softDeletes = false,
    this.deletedAtColumn = 'deleted_at',
    Map<String, void Function(WhereBuilder where)> globalScopes = const {},
    List<ModelObserver<T>> observers = const [],
  })  : casts = Map.unmodifiable(casts),
        fillable = Set.unmodifiable(fillable),
        hidden = Set.unmodifiable(hidden),
        globalScopes = Map.unmodifiable(globalScopes),
        _observers = List.of(observers);

  final String table;
  final ModelFactory<T> create;
  final String primaryKey;

  /// Whether the database generates the primary key on insert.
  final bool incrementing;

  /// Converters between database values and Dart values, by column: [Model.fill]
  /// receives the converted values and [Model.toMap]'s values are converted
  /// back when written.
  final Map<String, AttributeCast<Object?>> casts;

  /// The columns [Model.assign] may set (Laravel's `$fillable`).
  final Set<String> fillable;

  /// The columns left out of [Model.toJson] (Laravel's `$hidden`).
  final Set<String> hidden;

  /// Fills [createdAtColumn]/[updatedAtColumn] on save.
  final bool timestamps;
  final String createdAtColumn;
  final String updatedAtColumn;

  /// `delete()` sets [deletedAtColumn] instead of removing the row, and
  /// queries leave those rows out unless `withTrashed()`/`onlyTrashed()`.
  final bool softDeletes;
  final String deletedAtColumn;

  /// Conditions added to every query of this model (relations included),
  /// by name; `withoutGlobalScope(name)` removes one.
  final Map<String, void Function(WhereBuilder where)> globalScopes;

  final List<ModelObserver<T>> _observers;

  /// The observers notified of saves and deletes.
  List<ModelObserver<T>> get observers => List.unmodifiable(_observers);

  /// Adds an observer (e.g. at startup).
  void observe(ModelObserver<T> observer) => _observers.add(observer);

  /// Removes an observer added with [observe].
  bool unobserve(ModelObserver<T> observer) => _observers.remove(observer);

  /// A query on this model's table that returns models.
  ModelQuery<T> query(Connection connection) =>
      ModelQuery<T>._(connection, this, QueryBuilder2(connection, table));

  /// A new model (not saved yet) on [connection], with [values] set (all of
  /// them; see [Model.assign] for request input).
  T make(Connection connection, [Map<String, Object?> values = const {}]) {
    final model = create().._state.connection = connection;
    if (values.isNotEmpty) model._fillMerged(values);
    return model;
  }

  /// A model for a row read from the database. Columns named
  /// `__pivot_<column>` (selected by [BelongsToMany]) become its pivot
  /// values.
  T hydrate(Connection connection, Map<String, dynamic> row) {
    Map<String, Object?>? pivot;
    final columns = <String, Object?>{};
    row.forEach((column, value) {
      if (column.startsWith(_pivotPrefix)) {
        (pivot ??= {})[column.substring(_pivotPrefix.length)] = value;
      } else {
        columns[column] = value;
      }
    });
    final model = create();
    model._state
      ..connection = connection
      ..exists = true
      ..pivot = pivot;
    model._apply(columns);
    return model;
  }

  Map<String, Object?> _toDart(Map<String, Object?> values) => {
        for (final MapEntry(:key, :value) in values.entries)
          key: casts[key]?.fromDatabase(value) ?? value,
      };

  Map<String, Object?> _toDatabase(Map<String, Object?> values) => {
        for (final MapEntry(:key, :value) in values.entries)
          key: casts[key]?.toDatabase(value) ?? value,
      };
}

/// What the ORM keeps about one model besides its fields.
final class _ModelState {
  Connection? connection;
  bool exists = false;

  /// The database values last read or written, by column; columns the model
  /// does not map are kept here too.
  final Map<String, Object?> row = {};

  /// [Model.toMap] (as database values) when the model was last read or
  /// saved: what [Model.getDirty] compares with.
  Map<String, Object?> original = {};

  /// Loaded relations; a missing key means "not loaded".
  final Map<Relation<dynamic, dynamic>, Object?> relations = {};

  /// Pivot columns, when read through a [BelongsToMany].
  Map<String, Object?>? pivot;
}

const _deepEquality = DeepCollectionEquality();

/// Base class of Active Record models. A model implements three members:
///
/// - [modelDefinition]: its [ModelDefinition], usually a static field
///   (`static final definition = ModelDefinition<Post>(...)`);
/// - [toMap]: its columns and values;
/// - [fill]: the reverse, setting the fields from a row.
///
/// `fill(toMap())` must leave the model unchanged. Fields need an initial
/// value or a nullable type: a column that was not selected keeps it (and
/// is not written by [save]).
abstract class Model<T extends Model<T>> {
  final _ModelState _state = _ModelState();

  /// The model's definition; return the static one, not a new instance.
  ModelDefinition<T> get modelDefinition;

  /// The columns of the model and their values.
  Map<String, dynamic> toMap();

  /// Sets the fields from [row]: a database row (converted by the casts) or
  /// the result of [toMap] with some values replaced. It has every column
  /// [toMap] returns.
  void fill(Map<String, dynamic> row);

  /// A query of this model's table: Laravel's `newQuery()`. A static
  /// `Post.query(db)` cannot be inherited in Dart; declare one in the model
  /// (`static ModelQuery<Post> query(Connection db) => definition.query(db);`)
  /// or use `Post.definition.query(db)`.
  ModelQuery<T> newQuery(Connection connection) =>
      modelDefinition.query(connection);

  /// The connection this model was read with (or made for).
  Connection get connection =>
      _state.connection ??
      (throw StateError('${modelDefinition.table}: the model has no '
          'connection; create it with definition.make(db) or save(using: db).'));

  /// Whether the row exists in the database.
  bool get exists => _state.exists;

  /// The primary key value (null before the first save).
  Object? get key => _value(modelDefinition.primaryKey);

  /// Whether [column] was read from or written to the database.
  bool hasColumn(String column) => _state.row.containsKey(column);

  /// The database value of [column] when it was last read or saved; also
  /// the columns the model does not map (`selectRaw('count(*) as total')`).
  Object? getOriginal(String column) => _state.row[column];

  /// Columns changed since the model was read or saved, as database values.
  Map<String, Object?> getDirty() {
    final dirty = <String, Object?>{};
    _current().forEach((column, value) {
      if (!_state.original.containsKey(column) ||
          !_deepEquality.equals(_state.original[column], value)) {
        dirty[column] = value;
      }
    });
    return dirty;
  }

  bool isDirty([String? column]) {
    final dirty = getDirty();
    return column == null ? dirty.isNotEmpty : dirty.containsKey(column);
  }

  /// Mass assignment (Laravel's `fill()`): sets the columns of [input] that
  /// are in [ModelDefinition.fillable] and ignores the others, so request
  /// input cannot set `id`, `admin`, ...
  void assign(Map<String, Object?> input) {
    final fillable = modelDefinition.fillable;
    if (fillable.isEmpty) {
      throw StateError('${modelDefinition.table}: no fillable columns; '
          'list them in ModelDefinition(fillable: [...]).');
    }
    _fillMerged({
      for (final MapEntry(:key, :value) in input.entries)
        if (fillable.contains(key)) key: value,
    });
  }

  /// Inserts the model, or updates its changed columns. Only the changed
  /// columns are written, so a model read with `select([...])` keeps the
  /// columns it did not read. On insert, null fields are left out, so the
  /// columns get their defaults.
  ///
  /// Observers: `saving`, then `creating`/`created` or `updating`/`updated`
  /// (only when something changed), then `saved`. An exception thrown by an
  /// observer stops the save.
  Future<void> save({Connection? using}) async {
    if (using != null) _state.connection ??= using;
    final connection = using ?? this.connection;
    final definition = modelDefinition;
    final now = DateTime.now();
    await _notify((o) => o.saving(_self));

    if (!exists) {
      await _notify((o) => o.creating(_self));
      final values = {
        for (final MapEntry(:key, :value) in _current().entries)
          if (value != null) key: value,
      };
      if (definition.timestamps) {
        values.putIfAbsent(definition.createdAtColumn, () => now);
        values.putIfAbsent(definition.updatedAtColumn, () => now);
      }
      final pk = definition.primaryKey;
      final query = QueryBuilder2(connection, definition.table);
      Map<String, Object?> written;
      if (connection.getDriverName() == 'pgsql') {
        // Reads back the generated key and the column defaults.
        written = Map.of((await query.insertReturning(values)).single);
      } else if (definition.incrementing && values[pk] == null) {
        final id = await query.insertGetId<Object>(values, sequence: pk);
        written = {...values, pk: id};
      } else {
        await query.insert(values);
        written = values;
      }
      _state.exists = true;
      _apply(written);
      await _notify((o) => o.created(_self));
    } else if (isDirty()) {
      await _notify((o) => o.updating(_self));
      final dirty = getDirty();
      if (definition.timestamps &&
          !dirty.containsKey(definition.updatedAtColumn)) {
        dirty[definition.updatedAtColumn] = now;
      }
      await QueryBuilder2(connection, definition.table)
          .where(definition.primaryKey, _requireKey())
          .update(dirty);
      _apply(dirty);
      await _notify((o) => o.updated(_self));
    }
    await _notify((o) => o.saved(_self));
  }

  /// Whether the model is soft deleted.
  bool get trashed =>
      modelDefinition.softDeletes &&
      _value(modelDefinition.deletedAtColumn) != null;

  /// Deletes the row, or sets `deleted_at` when the model uses soft deletes.
  /// Observers: `deleting`, `deleted`.
  Future<void> delete({Connection? using}) async {
    if (!modelDefinition.softDeletes) return forceDelete(using: using);
    _requireExists();
    await _notify((o) => o.deleting(_self));
    await _writeNow({modelDefinition.deletedAtColumn: DateTime.now()}, using);
    await _notify((o) => o.deleted(_self));
  }

  /// Removes the row, even with soft deletes.
  Future<void> forceDelete({Connection? using}) async {
    _requireExists();
    await _notify((o) => o.deleting(_self));
    await QueryBuilder2(using ?? connection, modelDefinition.table)
        .where(modelDefinition.primaryKey, _requireKey())
        .delete();
    _state.exists = false;
    await _notify((o) => o.deleted(_self));
  }

  /// Clears `deleted_at`. Observers: `restoring`, `restored`.
  Future<void> restore({Connection? using}) async {
    if (!modelDefinition.softDeletes) {
      throw StateError('${modelDefinition.table} does not use soft deletes.');
    }
    _requireExists();
    await _notify((o) => o.restoring(_self));
    await _writeNow({modelDefinition.deletedAtColumn: null}, using);
    await _notify((o) => o.restored(_self));
  }

  /// Reads every column again and forgets the loaded relations.
  Future<void> refresh({Connection? using}) async {
    final definition = modelDefinition;
    final row = await QueryBuilder2(using ?? connection, definition.table)
        .where(definition.primaryKey, _requireKey())
        .first();
    if (row == null) {
      throw RecordsNotFoundException(
          '${definition.table} ${definition.primaryKey} = $key no longer exists.');
    }
    _state.row.clear();
    _state.relations.clear();
    _apply(row);
  }

  /// The model for an API response (Laravel's `toArray()`/`toJson()`):
  /// [toMap] without the [ModelDefinition.hidden] columns, plus the pivot
  /// values and the loaded relations by name. `DateTime` becomes ISO-8601
  /// text and an enum its name, so `jsonEncode(model)` works.
  Map<String, Object?> toJson() {
    final hidden = modelDefinition.hidden;
    final json = <String, Object?>{
      for (final MapEntry(:key, :value) in toMap().entries)
        if (!hidden.contains(key)) key: _jsonValue(value),
    };
    final pivot = _state.pivot;
    if (pivot != null) json['pivot'] = _jsonValue(pivot);
    _state.relations.forEach((relation, value) {
      json[relation.name] = _jsonValue(value);
    });
    return json;
  }

  @override
  String toString() => '${modelDefinition.table}(${toMap()})';

  T get _self => this as T;

  /// [toMap] as database values.
  Map<String, Object?> _current() => modelDefinition._toDatabase(toMap());

  /// The value of [column]: the mapped field, or else the last database
  /// value.
  Object? _value(String column) {
    final current = _current();
    return current.containsKey(column) ? current[column] : _state.row[column];
  }

  /// [_value] for a relation key, which must have been read.
  Object? _relationKey(String column) {
    if (exists && !hasColumn(column)) {
      throw StateError('${modelDefinition.table}.$column was not selected.');
    }
    return _value(column);
  }

  /// Sets [values] (database or Dart values) on the fields, keeping the
  /// other fields as they are.
  void _fillMerged(Map<String, Object?> values) {
    final definition = modelDefinition;
    fill(definition._toDart({...toMap(), ...values}));
  }

  /// Applies [written], database values just read or saved: the fields
  /// take them, they become the original values and the model is no longer
  /// dirty.
  void _apply(Map<String, Object?> written) {
    _fillMerged(written);
    _state.row.addAll(written);
    _state.original = _current();
  }

  /// Writes [values] (plus `updated_at`) right away. Only those columns
  /// become the original values: other unsaved changes stay dirty.
  Future<void> _writeNow(Map<String, Object?> values, Connection? using) async {
    final definition = modelDefinition;
    final changes = {
      ...values,
      if (definition.timestamps) definition.updatedAtColumn: DateTime.now(),
    };
    await QueryBuilder2(using ?? connection, definition.table)
        .where(definition.primaryKey, _requireKey())
        .update(changes);
    _fillMerged(changes);
    _state.row.addAll(changes);
    final current = _current();
    for (final column in changes.keys) {
      if (current.containsKey(column)) {
        _state.original[column] = current[column];
      }
    }
  }

  void _requireExists() {
    if (!exists) {
      throw StateError('${modelDefinition.table}: the model was not saved.');
    }
  }

  Object _requireKey() {
    final value = key;
    if (value == null) {
      throw StateError('${modelDefinition.table}: the primary key '
          '"${modelDefinition.primaryKey}" is not loaded.');
    }
    return value;
  }

  Future<void> _notify(
      FutureOr<void> Function(ModelObserver<T> observer) event) async {
    for (final observer in modelDefinition.observers) {
      await event(observer);
    }
  }
}

Object? _jsonValue(Object? value) => switch (value) {
      Model model => model.toJson(),
      DateTime date => date.toIso8601String(),
      Enum e => e.name,
      Map map => {
          for (final MapEntry(:key, :value) in map.entries)
            '$key': _jsonValue(value),
        },
      Iterable items => [for (final item in items) _jsonValue(item)],
      _ => value,
    };

/// Callbacks around saves and deletes of models of [T]. Override the ones
/// needed; an exception thrown in a `...ing` callback stops the operation,
/// and a callback may change fields before they are written.
///
/// ```dart
/// class AuditObserver extends ModelObserver<Post> {
///   @override
///   void updating(Post post) => post.editedBy = currentUser;
/// }
/// Post.definition.observe(AuditObserver());
/// ```
abstract class ModelObserver<T extends Model<T>> {
  const ModelObserver();

  FutureOr<void> saving(T model) {}
  FutureOr<void> saved(T model) {}
  FutureOr<void> creating(T model) {}
  FutureOr<void> created(T model) {}
  FutureOr<void> updating(T model) {}
  FutureOr<void> updated(T model) {}
  FutureOr<void> deleting(T model) {}
  FutureOr<void> deleted(T model) {}
  FutureOr<void> restoring(T model) {}
  FutureOr<void> restored(T model) {}
}
