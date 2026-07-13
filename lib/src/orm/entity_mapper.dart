/// Maps between database rows (`Map<String, dynamic>`) and entity objects of
/// type [T], **without code generation or reflection** — the application
/// supplies the conversion callbacks explicitly.
///
/// ```dart
/// class User {
///   int? id;
///   String name;
///   User({this.id, required this.name});
/// }
///
/// final userMapper = EntityMapper<User>(
///   table: 'users',
///   fromRow: (r) => User(id: r['id'] as int?, name: r['name'] as String),
///   toRow: (u) => {'name': u.name},          // omit the PK on insert/update
///   getId: (u) => u.id,
/// );
/// ```
class EntityMapper<T> {
  /// The database table backing this entity.
  final String table;

  /// The primary-key column (default `id`).
  final String primaryKey;

  /// Build an entity from a database row.
  final T Function(Map<String, dynamic> row) fromRow;

  /// Build a column map from an entity. Usually omit the primary key so the
  /// database assigns it on insert; include it only if you manage keys.
  final Map<String, dynamic> Function(T entity) toRow;

  /// Extract the primary-key value from an entity (`null` = not yet persisted).
  final dynamic Function(T entity) getId;

  const EntityMapper({
    required this.table,
    this.primaryKey = 'id',
    required this.fromRow,
    required this.toRow,
    required this.getId,
  });
}
