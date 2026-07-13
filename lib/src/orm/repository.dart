import 'dart:async';

import '../connection_interface.dart';
import '../query/query_builder.dart';
import 'entity_mapper.dart';

/// A thin data-mapper repository over the query builder — no code generation,
/// no reflection. Hydration is driven by an [EntityMapper].
///
/// ```dart
/// final repo = Repository<User>(await manager.connection(), userMapper);
/// final u = await repo.find(1);
/// await repo.save(User(name: 'Ada'));
/// await for (final user in repo.cursor()) { ... }
/// ```
class Repository<T> {
  final ConnectionInterface connection;
  final EntityMapper<T> mapper;

  Repository(this.connection, this.mapper);

  /// A query builder scoped to the entity's table. Use it to add clauses, then
  /// call [hydrate]/[hydrateAll] to map results back to entities, or the
  /// convenience methods below.
  QueryBuilder query() => connection.table(mapper.table);

  /// Map a single row (or null) to an entity (or null).
  T? hydrate(Map<String, dynamic>? row) =>
      row == null ? null : mapper.fromRow(row);

  /// Map a list of rows to entities.
  List<T> hydrateAll(List<Map<String, dynamic>> rows) =>
      rows.map(mapper.fromRow).toList();

  /// Find an entity by primary key, or `null`.
  Future<T?> find(dynamic id) async {
    final row = await query().where(mapper.primaryKey, '=', id).first();
    return hydrate(row);
  }

  /// Find an entity by primary key, or throw [StateError] if missing.
  Future<T> findOrFail(dynamic id) async {
    final entity = await find(id);
    if (entity == null) {
      throw StateError(
          'No ${mapper.table} row with ${mapper.primaryKey} = $id.');
    }
    return entity;
  }

  /// All entities in the table.
  Future<List<T>> all() async => hydrateAll(await query().get());

  /// Entities matching a simple `column <operator> value` predicate.
  Future<List<T>> findBy(String column, dynamic value,
      [String operator = '=']) async {
    final rows = await query().where(column, operator, value).get();
    return hydrateAll(rows);
  }

  /// The first entity matching a predicate, or `null`.
  Future<T?> firstBy(String column, dynamic value,
      [String operator = '=']) async {
    final row = await query().where(column, operator, value).first();
    return hydrate(row);
  }

  /// Stream entities using a server-side cursor (constant memory) when the
  /// driver supports it (see [QueryBuilder.cursor]).
  Stream<T> cursor([int? fetchSize]) =>
      query().cursor(fetchSize).map(mapper.fromRow);

  /// Insert an entity and return the generated primary key.
  Future<dynamic> insert(T entity) async {
    final data = mapper.toRow(entity);
    return await query().insertGetId(data, mapper.primaryKey);
  }

  /// Update the row matching the entity's primary key. Returns affected rows.
  Future<int> update(T entity) async {
    final id = mapper.getId(entity);
    if (id == null) {
      throw ArgumentError(
          'Cannot update a ${mapper.table} entity without a primary key.');
    }
    final data = mapper.toRow(entity);
    final affected =
        await query().where(mapper.primaryKey, '=', id).update(data);
    return affected is int ? affected : int.tryParse('$affected') ?? 0;
  }

  /// Insert when the entity has no primary key, otherwise update. Returns the
  /// primary key (generated on insert, existing on update).
  Future<dynamic> save(T entity) async {
    final id = mapper.getId(entity);
    if (id == null) {
      return await insert(entity);
    }
    await update(entity);
    return id;
  }

  /// Delete the row matching the entity's primary key.
  Future<int> delete(T entity) => deleteById(mapper.getId(entity));

  /// Delete the row with the given primary key. Returns affected rows.
  Future<int> deleteById(dynamic id) async {
    return await query().where(mapper.primaryKey, '=', id).delete();
  }

  /// Count all rows in the table.
  Future<int> count() async => await query().count();
}
