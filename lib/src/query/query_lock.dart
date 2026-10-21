/// Row-locking clause of a SELECT (`FOR UPDATE` / `FOR SHARE`) with its
/// optional modifiers.
///
/// Built by `QueryBuilder.lockForUpdate`, `sharedLock`, `skipLocked` and
/// `noWait`; each dialect grammar renders it.
class QueryLock {
  const QueryLock({
    this.forUpdate = true,
    this.skipLocked = false,
    this.noWait = false,
    this.of = const <String>[],
  }) : assert(!(skipLocked && noWait),
            'SKIP LOCKED and NOWAIT cannot be combined.');

  /// `FOR UPDATE` when true, `FOR SHARE` when false.
  final bool forUpdate;

  /// `SKIP LOCKED`: rows locked by another transaction are left out instead
  /// of waiting for them (PostgreSQL 9.5+, MySQL 8.0+).
  final bool skipLocked;

  /// `NOWAIT`: fail immediately instead of waiting for a locked row.
  final bool noWait;

  /// `OF table, ...`: lock only the rows of these tables (or aliases).
  final List<String> of;

  QueryLock copyWith({
    bool? forUpdate,
    bool? skipLocked,
    bool? noWait,
    List<String>? of,
  }) {
    final nextSkipLocked = skipLocked ?? this.skipLocked;
    final nextNoWait = noWait ?? this.noWait;
    if (nextSkipLocked && nextNoWait) {
      throw ArgumentError('SKIP LOCKED and NOWAIT cannot be combined.');
    }
    return QueryLock(
      forUpdate: forUpdate ?? this.forUpdate,
      skipLocked: nextSkipLocked,
      noWait: nextNoWait,
      of: of ?? this.of,
    );
  }

  @override
  String toString() =>
      'QueryLock(forUpdate: $forUpdate, skipLocked: $skipLocked, '
      'noWait: $noWait, of: $of)';
}

/// Mode of a PostgreSQL `LOCK TABLE` (`QueryBuilder.lockTable`), from the
/// weakest to the strongest. See the "Table-Level Locks" table of the
/// PostgreSQL manual for what each one conflicts with.
enum TableLockMode {
  /// `ACCESS SHARE`: the lock of a plain SELECT; conflicts only with
  /// [accessExclusive].
  accessShare('access share'),

  /// `ROW SHARE`: the lock of `SELECT ... FOR UPDATE/SHARE` and of foreign
  /// key checks.
  rowShare('row share'),

  /// `ROW EXCLUSIVE`: the lock of INSERT, UPDATE and DELETE.
  rowExclusive('row exclusive'),

  /// `SHARE UPDATE EXCLUSIVE`: VACUUM, ANALYZE, `CREATE INDEX CONCURRENTLY`.
  shareUpdateExclusive('share update exclusive'),

  /// `SHARE`: blocks writes, allows reads and other SHARE locks.
  share('share'),

  /// `SHARE ROW EXCLUSIVE`: blocks writes; one holder at a time.
  shareRowExclusive('share row exclusive'),

  /// `EXCLUSIVE`: only plain reads (ACCESS SHARE) go on; also blocks
  /// `FOR UPDATE/SHARE` and foreign key checks of other tables.
  exclusive('exclusive'),

  /// `ACCESS EXCLUSIVE`: blocks everything, reads included (the default of
  /// a bare `LOCK TABLE`).
  accessExclusive('access exclusive');

  const TableLockMode(this.sql);

  /// The mode as written in `LOCK TABLE ... IN <sql> MODE`.
  final String sql;
}
