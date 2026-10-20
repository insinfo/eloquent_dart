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
