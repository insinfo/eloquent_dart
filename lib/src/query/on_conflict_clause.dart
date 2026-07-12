/// Describes a PostgreSQL/SQLite `ON CONFLICT` clause (and, on MySQL, is mapped
/// to `ON DUPLICATE KEY UPDATE` by the grammar).
///
/// Two conflict targets are supported and mutually exclusive:
///  * [columns]: `ON CONFLICT (col1, col2)` — the unique/exclusion columns.
///  * [constraint]: `ON CONFLICT ON CONSTRAINT name` — a named constraint.
///
/// The action is either:
///  * [doNothing] == true  -> `DO NOTHING`.
///  * [updateValues] != null -> `DO UPDATE SET ...` (with optional [updateWhereRaw]).
///
/// [updateValues] values may be raw [QueryExpression]s (e.g.
/// `db.raw('table.last_id + 1')`) so that expressions like
/// `DO UPDATE SET last_id = table.last_id + 1` are possible.
class OnConflictClause {
  /// Conflict target columns, e.g. `['ano']` -> `ON CONFLICT (ano)`.
  final List<String> columns;

  /// Named constraint target, e.g. `ON CONFLICT ON CONSTRAINT my_uq`.
  final String? constraint;

  /// When true, emits `DO NOTHING`.
  final bool doNothing;

  /// When set, emits `DO UPDATE SET <col> = <value>, ...`.
  final Map<String, dynamic>? updateValues;

  /// Optional raw predicate appended as `WHERE <sql>` to the `DO UPDATE`.
  final String? updateWhereRaw;

  const OnConflictClause({
    this.columns = const [],
    this.constraint,
    this.doNothing = false,
    this.updateValues,
    this.updateWhereRaw,
  });

  OnConflictClause copyWith({
    List<String>? columns,
    String? constraint,
    bool? doNothing,
    Map<String, dynamic>? updateValues,
    String? updateWhereRaw,
  }) {
    return OnConflictClause(
      columns: columns ?? this.columns,
      constraint: constraint ?? this.constraint,
      doNothing: doNothing ?? this.doNothing,
      updateValues: updateValues ?? this.updateValues,
      updateWhereRaw: updateWhereRaw ?? this.updateWhereRaw,
    );
  }
}
