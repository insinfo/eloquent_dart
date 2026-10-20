/// Active Record models without code generation or reflection: a model
/// declares its table and constructor ([ModelDefinition]) and exposes typed
/// getters/setters over [Model.readAttribute]/[Model.writeAttribute];
/// relations are declared once as static fields ([HasOne], [HasMany],
/// [BelongsTo]) and loaded per model or in batches.
///
/// The Data Mapper option ([Repository] and [EntityMapper]) stays available
/// for plain classes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:eloquent/eloquent.dart';

part 'casts.dart';
part 'model_query.dart';
part 'relations.dart';

/// Creates a model from its state: the model's constructor, e.g. `User.new`.
typedef ModelFactory<T extends Model> = T Function(ModelState state);

/// Table, key, constructor and casts of a model.
///
/// ```dart
/// class User extends Model {
///   User(super.state);
///
///   static final definition = ModelDefinition<User>(
///     table: 'users',
///     create: User.new,
///     casts: {'ativo': Casts.boolean},
///   );
///
///   int get id => readAttribute<int>('id');
///   String get name => readAttribute<String>('name');
///   set name(String value) => writeAttribute('name', value);
/// }
/// ```
final class ModelDefinition<T extends Model> {
  ModelDefinition({
    required this.table,
    required this.create,
    this.primaryKey = 'id',
    this.incrementing = true,
    Map<String, AttributeCast<Object?>> casts = const {},
    this.timestamps = false,
    this.createdAtColumn = 'created_at',
    this.updatedAtColumn = 'updated_at',
    this.softDeletes = false,
    this.deletedAtColumn = 'deleted_at',
    Map<String, void Function(WhereBuilder where)> globalScopes = const {},
    List<ModelObserver<T>> observers = const [],
  })  : casts = Map.unmodifiable(casts),
        globalScopes = Map.unmodifiable(globalScopes),
        _observers = List.of(observers);

  final String table;
  final ModelFactory<T> create;
  final String primaryKey;

  /// Whether the database generates the primary key on insert.
  final bool incrementing;

  /// Converters between database values and Dart values, by column.
  final Map<String, AttributeCast<Object?>> casts;

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

  /// A new model (not saved yet) with [attributes].
  T make(Connection connection, [Map<String, Object?> attributes = const {}]) {
    final model = create(ModelState._(connection, this, {}, exists: false));
    model.fill(attributes);
    return model;
  }

  /// A model for a row read from the database. Columns named
  /// `__pivot_<column>` (selected by [BelongsToMany]) become its pivot
  /// values.
  T hydrate(Connection connection, Map<String, dynamic> row) {
    Map<String, Object?>? pivot;
    final attributes = <String, Object?>{};
    row.forEach((column, value) {
      if (column.startsWith(_pivotPrefix)) {
        (pivot ??= {})[column.substring(_pivotPrefix.length)] = value;
      } else {
        attributes[column] = value;
      }
    });
    return create(ModelState._(connection, this, attributes, exists: true)
      .._pivot = pivot);
  }
}

/// The data of one model: attributes, the values last read or saved, whether
/// the row exists and the loaded relations. Created by the ORM and passed to
/// the model's constructor.
final class ModelState {
  ModelState._(this._connection, this._definition, this._attributes,
      {required bool exists})
      : _exists = exists,
        _original = exists ? Map.of(_attributes) : {};

  Connection _connection;
  final ModelDefinition<Model> _definition;
  Map<String, Object?> _attributes;
  Map<String, Object?> _original;
  bool _exists;

  /// Loaded relations; a missing key means "not loaded".
  final Map<Relation<Model, Model>, Object?> _relations = {};

  /// Pivot columns, when read through a [BelongsToMany].
  Map<String, Object?>? _pivot;

  Object? _raw(String column) {
    if (!_attributes.containsKey(column)) {
      throw StateError(_exists
          ? '${_definition.table}.$column was not selected.'
          : '${_definition.table}.$column is not set.');
    }
    return _attributes[column];
  }
}

const _deepEquality = DeepCollectionEquality();

/// Base class of Active Record models.
abstract class Model {
  Model(this._state);

  final ModelState _state;

  ModelDefinition<Model> get modelDefinition => _state._definition;

  /// The connection this model was read with (or made for).
  Connection get connection => _state._connection;

  /// Whether the row exists in the database.
  bool get exists => _state._exists;

  /// The primary key value (null before the first save).
  Object? get key => _state._attributes[modelDefinition.primaryKey];

  /// The raw attributes (database values).
  Map<String, Object?> get attributes => Map.unmodifiable(_state._attributes);

  bool hasAttribute(String column) => _state._attributes.containsKey(column);

  /// [column] converted by its cast, as [T].
  ///
  /// A column that was not selected throws [StateError] (it is not the same
  /// as `null`). On a new model an unset column reads as `null` when [T] is
  /// nullable.
  T readAttribute<T>(String column) {
    if (!_state._attributes.containsKey(column) && !exists && null is T) {
      return null as T;
    }
    final value = _castGet(column, _state._raw(column));
    if (value is! T) {
      throw StateError('${modelDefinition.table}.$column is '
          '${value.runtimeType} ($value), not $T. Add a cast to the '
          'ModelDefinition (Casts.boolean, Casts.decimal, ...).');
    }
    return value;
  }

  /// Sets [column] (converted by its cast); it is saved on the next [save].
  void writeAttribute(String column, Object? value) {
    final cast = modelDefinition.casts[column];
    _state._attributes[column] = cast == null ? value : cast.toDatabase(value);
  }

  /// Sets several attributes.
  void fill(Map<String, Object?> values) {
    values.forEach(writeAttribute);
  }

  /// Attributes changed since the model was read or saved.
  Map<String, Object?> getDirty() {
    final dirty = <String, Object?>{};
    _state._attributes.forEach((column, value) {
      if (!_state._original.containsKey(column) ||
          !_deepEquality.equals(_state._original[column], value)) {
        dirty[column] = value;
      }
    });
    return dirty;
  }

  bool isDirty([String? column]) {
    final dirty = getDirty();
    return column == null ? dirty.isNotEmpty : dirty.containsKey(column);
  }

  /// Inserts the model, or updates its changed attributes. Only the changed
  /// columns are written, so a model read with `select([...])` keeps the
  /// columns it did not read.
  ///
  /// Observers: `saving`, then `creating`/`created` or `updating`/`updated`
  /// (only when something changed), then `saved`. An exception thrown by an
  /// observer stops the save.
  Future<void> save({Connection? using}) async {
    final connection = using ?? this.connection;
    final modelDefinition = this.modelDefinition;
    final now = DateTime.now();
    await _notify((o) => o.saving(this));

    if (!exists) {
      await _notify((o) => o.creating(this));
      if (modelDefinition.timestamps) {
        _state._attributes
            .putIfAbsent(modelDefinition.createdAtColumn, () => now);
        _state._attributes
            .putIfAbsent(modelDefinition.updatedAtColumn, () => now);
      }
      final values = Map<String, Object?>.of(_state._attributes);
      final pk = modelDefinition.primaryKey;
      final query = QueryBuilder2(connection, modelDefinition.table);
      if (connection.getDriverName() == 'pgsql') {
        // Reads back the generated key and the column defaults.
        final rows = await query.insertReturning(values);
        _state._attributes = Map<String, Object?>.of(rows.single);
      } else if (modelDefinition.incrementing && values[pk] == null) {
        values.remove(pk);
        final id = await query.insertGetId<Object>(values, sequence: pk);
        _state._attributes[pk] = id;
      } else {
        await query.insert(values);
      }
      _state._exists = true;
      _state._original = Map.of(_state._attributes);
      await _notify((o) => o.created(this));
    } else if (isDirty()) {
      await _notify((o) => o.updating(this));
      final dirty = getDirty();
      if (modelDefinition.timestamps &&
          !dirty.containsKey(modelDefinition.updatedAtColumn)) {
        _state._attributes[modelDefinition.updatedAtColumn] = now;
        dirty[modelDefinition.updatedAtColumn] = now;
      }
      await QueryBuilder2(connection, modelDefinition.table)
          .where(modelDefinition.primaryKey, _requireKey())
          .update(dirty);
      _state._original = Map.of(_state._attributes);
      await _notify((o) => o.updated(this));
    }
    await _notify((o) => o.saved(this));
  }

  /// Whether the model is soft deleted.
  bool get trashed =>
      modelDefinition.softDeletes &&
      _state._attributes[modelDefinition.deletedAtColumn] != null;

  /// Deletes the row, or sets `deleted_at` when the model uses soft deletes.
  /// Observers: `deleting`, `deleted`.
  Future<void> delete({Connection? using}) async {
    if (!modelDefinition.softDeletes) return forceDelete(using: using);
    _requireExists();
    await _notify((o) => o.deleting(this));
    await _writeNow({modelDefinition.deletedAtColumn: DateTime.now()}, using);
    await _notify((o) => o.deleted(this));
  }

  /// Removes the row, even with soft deletes.
  Future<void> forceDelete({Connection? using}) async {
    _requireExists();
    await _notify((o) => o.deleting(this));
    await QueryBuilder2(using ?? connection, modelDefinition.table)
        .where(modelDefinition.primaryKey, _requireKey())
        .delete();
    _state._exists = false;
    await _notify((o) => o.deleted(this));
  }

  /// Clears `deleted_at`. Observers: `restoring`, `restored`.
  Future<void> restore({Connection? using}) async {
    if (!modelDefinition.softDeletes) {
      throw StateError('${modelDefinition.table} does not use soft deletes.');
    }
    _requireExists();
    await _notify((o) => o.restoring(this));
    await _writeNow({modelDefinition.deletedAtColumn: null}, using);
    await _notify((o) => o.restored(this));
  }

  /// Writes [values] (plus `updated_at`) right away and keeps them as saved.
  Future<void> _writeNow(Map<String, Object?> values, Connection? using) async {
    final definition = modelDefinition;
    final changes = {
      ...values,
      if (definition.timestamps) definition.updatedAtColumn: DateTime.now(),
    };
    await QueryBuilder2(using ?? connection, definition.table)
        .where(definition.primaryKey, _requireKey())
        .update(changes);
    _state._attributes.addAll(changes);
    changes.forEach((column, value) => _state._original[column] = value);
  }

  void _requireExists() {
    if (!exists) {
      throw StateError('${modelDefinition.table}: the model was not saved.');
    }
  }

  Future<void> _notify(
      FutureOr<void> Function(ModelObserver<Model> observer) event) async {
    for (final observer in modelDefinition.observers) {
      await event(observer);
    }
  }

  /// Reads every attribute again and forgets the loaded relations.
  Future<void> refresh({Connection? using}) async {
    final row = await QueryBuilder2(using ?? connection, modelDefinition.table)
        .where(modelDefinition.primaryKey, _requireKey())
        .first();
    if (row == null) {
      throw RecordsNotFoundException(
          '${modelDefinition.table} ${modelDefinition.primaryKey} = $key no longer exists.');
    }
    _state._attributes = Map<String, Object?>.of(row);
    _state._original = Map.of(_state._attributes);
    _state._relations.clear();
  }

  /// The attributes (converted by their casts) and the loaded relations, by
  /// relation name.
  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      for (final column in _state._attributes.keys)
        column: _castGet(column, _state._attributes[column]),
    };
    final pivot = _state._pivot;
    if (pivot != null) map['pivot'] = Map.of(pivot);
    _state._relations.forEach((relation, value) {
      map[relation.name] = switch (value) {
        Model model => model.toMap(),
        List<Model> models => [for (final m in models) m.toMap()],
        _ => value,
      };
    });
    return map;
  }

  Object _requireKey() {
    final value = key;
    if (value == null) {
      throw StateError('${modelDefinition.table}: the primary key '
          '"${modelDefinition.primaryKey}" is not loaded.');
    }
    return value;
  }

  Object? _castGet(String column, Object? raw) {
    final cast = modelDefinition.casts[column];
    return cast == null ? raw : cast.fromDatabase(raw);
  }

  @override
  String toString() => '${modelDefinition.table}(${_state._attributes})';
}

/// Callbacks around saves and deletes of models of [T]. Override the ones
/// needed; an exception thrown in a `...ing` callback stops the operation.
///
/// ```dart
/// class AuditObserver extends ModelObserver<User> {
///   @override
///   void updating(User user) => user.writeAttribute('alterado_por', atual);
/// }
/// User.definition.observe(AuditObserver());
/// ```
abstract class ModelObserver<T extends Model> {
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
