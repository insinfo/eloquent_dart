import 'query_exception.dart';

/// A statement violated a unique index or constraint (PostgreSQL SQLSTATE
/// `23505`, MySQL/MariaDB errors 1062 and 1586), as Laravel's
/// `UniqueConstraintViolationException`.
///
/// Thrown by the connection in place of the driver's exception, which stays
/// in [previous]; `toString()` keeps the driver's text, so code that looks
/// for `23505` or the constraint name in the message still finds it. Other
/// driver errors are not wrapped.
///
/// ```dart
/// try {
///   await db.table('normas.tipo_norma').insert(item.toMap());
/// } on UniqueConstraintViolationException catch (e) {
///   if (e.constraint != 'tipo_norma_nome_uq') rethrow;
///   throw TipoNormaOperacaoException('Já existe um tipo com esse nome.');
/// }
/// ```
///
/// On PostgreSQL an error aborts the transaction it happens in: to catch it
/// and go on in the same transaction, run the statement in a nested
/// `transaction` (a SAVEPOINT), as `QueryBuilder.createOrFirst` does.
class UniqueConstraintViolationException extends QueryException {
  UniqueConstraintViolationException(
      String sql, dynamic bindings, dynamic previous,
      {this.constraint})
      : super(sql, bindings, previous);

  /// The violated constraint or unique index: PostgreSQL's constraint name;
  /// on MySQL the key name of the message (`Duplicate entry 'x' for key
  /// 'table.key'`, without the table). Null when the driver does not say.
  final String? constraint;

  /// SQLSTATE of a unique violation.
  static const postgresSqlState = '23505';

  /// MySQL/MariaDB `ER_DUP_ENTRY` and `ER_DUP_ENTRY_WITH_KEY_NAME`.
  static const mySqlErrorCodes = {1062, 1586};

  static final _mySqlKey = RegExp(r"for key '([^']*)'");

  /// The exception for driver error [error] of [sql], or null when [error]
  /// is not a unique violation.
  static UniqueConstraintViolationException? fromDriverError(
      Object error, String sql, dynamic bindings) {
    if (error is UniqueConstraintViolationException) return error;
    final code = _field(error, (e) => e.sqlState) ??
        _field(error, (e) => e.code) ??
        _field(error, (e) => e.errorCode);
    UniqueConstraintViolationException? mapped;
    if (code == postgresSqlState) {
      mapped = UniqueConstraintViolationException(sql, bindings, error,
          constraint: _postgresConstraint(error));
    } else if (code is int && mySqlErrorCodes.contains(code)) {
      final key = _mySqlKey.firstMatch('$error')?.group(1);
      mapped = UniqueConstraintViolationException(sql, bindings, error,
          constraint: key?.substring(key.lastIndexOf('.') + 1));
    }
    if (mapped != null) _byDriverError[error] = mapped;
    return mapped;
  }

  /// The exception [fromDriverError] made for the driver's [error], if any.
  /// The postgres and postgres_v3 adapters end their transaction with the
  /// failed statement's original exception, so `transaction()` swaps it for
  /// the one its callback saw.
  static UniqueConstraintViolationException? mappedFrom(Object error) =>
      error is UniqueConstraintViolationException
          ? error
          : _byDriverError[error];

  static final _byDriverError = Expando<UniqueConstraintViolationException>();

  /// `constraintName` on postgres, postgres_v3 and dpgsql; dargres keeps the
  /// server's fields in `serverMessage`.
  static String? _postgresConstraint(Object error) {
    final name = _field(error, (e) => e.constraintName) ??
        _field(error, (e) => e.serverMessage.constraint);
    return name is String ? name : null;
  }

  /// A String or int field of [error], or null when it has no such field.
  static Object? _field(Object error, dynamic Function(dynamic e) read) {
    try {
      final value = read(error);
      return value is String || value is int ? value : null;
    } catch (_) {
      // The exception has no such field.
      return null;
    }
  }

  @override
  String toString() => constraint == null
      ? 'UniqueConstraintViolationException: $previous'
      : 'UniqueConstraintViolationException ($constraint): $previous';
}
