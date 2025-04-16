// File: C:\MyDartProjects\eloquent\lib\src\doctrine\exceptions\doctrine_exceptions.dart

/// Base exception class for all Doctrine DBAL related errors in this package.
class DoctrineDbalException implements Exception {
  final String message;
  /// Optional original error from the underlying driver or system.
  final dynamic cause; // Reverted to dynamic (can hold null)
  /// Optional stack trace associated with the original error.
  final StackTrace? stackTrace;

  // Corrected Constructor: message is required positional, others optional positional
  DoctrineDbalException(this.message, [this.cause, this.stackTrace]);

  @override
  String toString() {
    String result = 'DoctrineDbalException: $message';
    if (cause != null) {
      result += '\nCause: $cause';
    }
    // Optionally include stack trace if needed for debugging, but can be noisy
    // if (stackTrace != null) {
    //   result += '\nStack Trace:\n$stackTrace';
    // }
    return result;
  }
}

// --- Driver & Connection Level Exceptions ---

/// Base class for driver-level errors (issues communicating with the DB).
class DriverException extends DoctrineDbalException {
  /// SQLSTATE error code, if available.
  final String? sqlState;
  /// Vendor-specific error code, if available.
  final int? vendorCode;

  // Corrected Super Call: Pass values positionally
  DriverException(
    String message, [
    dynamic cause, // dynamic is fine here
    StackTrace? stackTrace,
    this.sqlState,
    this.vendorCode,
  ]) : super(message, cause, stackTrace); // Pass values explicitly

   @override
  String toString() {
     String base = 'DriverException: $message';
     if (sqlState != null) base += ' (SQLSTATE[$sqlState])';
     if (vendorCode != null) base += ' (Vendor Code[$vendorCode])';
     if (cause != null) base += '\nCause: $cause';
     return base;
  }
}

/// Base class for connection-specific errors.
class ConnectionException extends DriverException {
  // Corrected Super Call
  ConnectionException(
    String message, [
    dynamic cause, // dynamic is fine here
    StackTrace? stackTrace,
    String? sqlState,
    int? vendorCode,
  ]) : super(message, cause, stackTrace, sqlState, vendorCode); // Pass values

   @override String toString() => 'ConnectionException: $message';
}

/// Exception for when a connection is lost. Might be retryable.
class ConnectionLost extends ConnectionException implements RetryableException {
   // Corrected Super Call
   ConnectionLost(
       String message, [
       dynamic cause, // dynamic is fine here
       StackTrace? stackTrace,
       String? sqlState,
       int? vendorCode,
     ]) : super(message, cause, stackTrace, sqlState, vendorCode);

  factory ConnectionLost.fromCause(dynamic cause, [StackTrace? trace]) {
    // Ensure factory passes required message
    return ConnectionLost('Connection lost', cause, trace);
  }
   @override String toString() => 'ConnectionLost: $message';
}

/// Exception thrown when attempting a commit that will fail due to prior rollback-only marking.
class CommitFailedRollbackOnly extends ConnectionException {
   // Corrected Super Call
   CommitFailedRollbackOnly(
       String message, [
       dynamic cause, // dynamic is fine here
       StackTrace? stackTrace,
       String? sqlState,
       int? vendorCode,
     ]) : super(message, cause, stackTrace, sqlState, vendorCode);

  // Renamed factory from .new to .create
  factory CommitFailedRollbackOnly.create() {
    return CommitFailedRollbackOnly('Commit failed: Transaction is marked rollback-only.');
  }
}

/// Exception for trying to use savepoints when the driver does not support them.
class SavepointsNotSupported extends ConnectionException {
  // Corrected Super Call
  SavepointsNotSupported(String message) : super(message);

  // Renamed factory from .new to .create
  factory SavepointsNotSupported.create() {
    return SavepointsNotSupported('Savepoints are not supported by this driver.');
  }
}

/// Exception for when a required database is not specified or does not exist upon connection.
class DatabaseRequired extends ConnectionException {
   // Corrected Super Call
   DatabaseRequired(String message) : super(message);
   factory DatabaseRequired.forConnection() {
       return DatabaseRequired('Database name is required for this connection.');
   }
}

/// Exception for when the specified database does not exist.
class DatabaseDoesNotExist extends ConnectionException {
   // Corrected Super Call
   DatabaseDoesNotExist(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
       : super(message, cause, stackTrace, sqlState, vendorCode);

   factory DatabaseDoesNotExist.forDatabase(String dbName) {
       return DatabaseDoesNotExist('Database "$dbName" does not exist.');
   }
}

/// Exception for when an operation requires an active transaction, but none exists.
class NoActiveTransaction extends ConnectionException {
   // Corrected Super Call
   NoActiveTransaction(String message) : super(message);
   // Renamed factory from .new to .create
   factory NoActiveTransaction.create() {
       return NoActiveTransaction('There is no active transaction.');
   }
}

/// Exception for when a transaction is rolled back unexpectedly.
class TransactionRolledBack extends ConnectionException {
   // Corrected Super Call
   TransactionRolledBack(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
       : super(message, cause, stackTrace, sqlState, vendorCode);
   factory TransactionRolledBack.duringCommit() {
       return TransactionRolledBack('Transaction rolled back during commit attempt.');
   }
}

/// Exception for when attempting to modify data on a read-only connection.
class ReadOnlyException extends ConnectionException {
   // Corrected Super Call
   ReadOnlyException(String message) : super(message);
   // Renamed factory from .new to .create
   factory ReadOnlyException.create() {
       return ReadOnlyException('Cannot execute write operation on a read-only connection.');
   }
}

// --- Server Level Exceptions ---

/// Base class for errors reported by the database server during query execution.
class ServerException extends DriverException {
  // Corrected Super Call
  ServerException(
    String message, [
    dynamic cause, // dynamic is fine here
    StackTrace? stackTrace,
    String? sqlState,
    int? vendorCode,
  ]) : super(message, cause, stackTrace, sqlState, vendorCode);

  @override String toString() => 'ServerException: $message';
}

/// Exception for a deadlock error during a transaction. Often retryable.
class DeadlockException extends ServerException implements RetryableException {
  // Corrected Super Call
  DeadlockException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);

  factory DeadlockException.fromCause(dynamic cause, [StackTrace? trace]) {
    return DeadlockException('Deadlock detected', cause, trace);
  }
   @override String toString() => 'DeadlockException: $message';
}

/// Exception for a lock wait timeout error during a transaction. Often retryable.
class LockWaitTimeoutException extends ServerException implements RetryableException {
  // Corrected Super Call
  LockWaitTimeoutException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   factory LockWaitTimeoutException.fromCause(dynamic cause, [StackTrace? trace]) {
     return LockWaitTimeoutException('Lock wait timeout exceeded', cause, trace);
   }
    @override String toString() => 'LockWaitTimeoutException: $message';
}

/// Base class for constraint violation errors.
class ConstraintViolationException extends ServerException {
  // Corrected Super Call
  ConstraintViolationException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   @override String toString() => 'ConstraintViolationException: $message';
}

/// Exception for foreign key constraint violations.
class ForeignKeyConstraintViolationException extends ConstraintViolationException {
  // Corrected Super Call
  ForeignKeyConstraintViolationException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   factory ForeignKeyConstraintViolationException.fromCause(dynamic cause, [StackTrace? trace]) {
     return ForeignKeyConstraintViolationException('Foreign key constraint violation', cause, trace);
   }
   @override String toString() => 'ForeignKeyConstraintViolationException: $message';
}

/// Exception for NOT NULL constraint violations.
class NotNullConstraintViolationException extends ConstraintViolationException {
  // Corrected Super Call
  NotNullConstraintViolationException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   factory NotNullConstraintViolationException.fromCause(dynamic cause, [StackTrace? trace]) {
     return NotNullConstraintViolationException('NOT NULL constraint violation', cause, trace);
   }
   @override String toString() => 'NotNullConstraintViolationException: $message';
}

/// Exception for unique constraint violations.
class UniqueConstraintViolationException extends ConstraintViolationException {
  // Corrected Super Call
  UniqueConstraintViolationException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   factory UniqueConstraintViolationException.fromCause(dynamic cause, [StackTrace? trace]) {
     return UniqueConstraintViolationException('Unique constraint violation', cause, trace);
   }
   @override String toString() => 'UniqueConstraintViolationException: $message';
}

/// Exception for syntax errors in SQL execution.
class SyntaxErrorException extends ServerException {
  // Corrected Super Call
  SyntaxErrorException(String message, [dynamic cause, StackTrace? stackTrace, String? sqlState, int? vendorCode])
      : super(message, cause, stackTrace, sqlState, vendorCode);
   factory SyntaxErrorException.fromCause(dynamic cause, [StackTrace? trace]) {
     return SyntaxErrorException('Syntax error or access violation', cause, trace);
   }
    @override String toString() => 'SyntaxErrorException: $message';
}

// --- Schema Level Exceptions ---

/// Base class for schema definition and manipulation errors.
class SchemaException extends DoctrineDbalException {
  // Corrected Super Call
  SchemaException(String message, [dynamic cause, StackTrace? stackTrace])
      : super(message, cause, stackTrace);
   @override String toString() => 'SchemaException: $message';
}

/// Base class for errors related to database object existence.
abstract class DatabaseObjectException extends SchemaException {
   // Corrected Super Call
   DatabaseObjectException(super.message) : super();
}

/// Exception for when a database object (table, sequence, etc.) already exists.
class DatabaseObjectExistsException extends DatabaseObjectException {
  // Corrected Super Call
  DatabaseObjectExistsException(super.message) : super();
}

/// Exception for when a database object (table, sequence, etc.) is not found.
class DatabaseObjectNotFoundException extends DatabaseObjectException {
  // Corrected Super Call
  DatabaseObjectNotFoundException(super.message) : super();
}

/// Exception for when a table already exists.
class TableExistsException extends DatabaseObjectExistsException {
  TableExistsException(String tableName) : super('Table "$tableName" already exists.');
}

/// Exception for when a table is not found.
class TableNotFoundException extends DatabaseObjectNotFoundException {
  TableNotFoundException(String tableName) : super('Table "$tableName" does not exist.');
}

/// Exception for when a schema does not exist.
class SchemaDoesNotExist extends DatabaseObjectNotFoundException {
   SchemaDoesNotExist(String schemaName) : super('Schema "$schemaName" does not exist.');
}

/// Exception for invalid field name usage.
class InvalidFieldNameException extends SchemaException {
  InvalidFieldNameException(String fieldName) : super('Invalid field name "$fieldName".');
}

/// Exception for when a field name is not unique where required.
class NonUniqueFieldNameException extends SchemaException {
   NonUniqueFieldNameException(String fieldName) : super('Field name "$fieldName" is not unique.');
}

/// Exception for invalid column index usage.
class InvalidColumnIndex extends SchemaException {
   InvalidColumnIndex(int index) : super('Invalid column index "$index".');
}

/// Base class for exceptions related to invalid column type definitions.
class InvalidColumnTypeException extends SchemaException {
  InvalidColumnTypeException(String typeName, String? reason)
      : super('Invalid definition for column type "$typeName"${reason != null ? ": $reason" : "."}');
}

/// Exception for when a required column length is missing.
class ColumnLengthRequiredException extends InvalidColumnTypeException {
  ColumnLengthRequiredException(String typeName)
      : super(typeName, 'Length is required');
}

/// Exception for when a required column precision is missing.
class ColumnPrecisionRequiredException extends InvalidColumnTypeException {
  ColumnPrecisionRequiredException(String typeName)
      : super(typeName, 'Precision is required');
}

/// Exception for when a required column scale is missing.
class ColumnScaleRequiredException extends InvalidColumnTypeException {
  ColumnScaleRequiredException(String typeName)
      : super(typeName, 'Scale is required');
}

/// Exception for when values are required for a type (e.g., ENUM) but not provided.
class ColumnValuesRequiredException extends InvalidColumnTypeException {
  ColumnValuesRequiredException(String typeName)
      : super(typeName, 'Column values are required');
}

/// Exception for general invalid column declaration issues.
class InvalidColumnDeclarationException extends SchemaException {
  // Corrected Super Call
  InvalidColumnDeclarationException(String message, [dynamic cause, StackTrace? stackTrace])
      : super(message, cause, stackTrace);

  factory InvalidColumnDeclarationException.fromInvalidColumnType(String columnName, InvalidColumnTypeException cause) {
    return InvalidColumnDeclarationException(
      'Invalid declaration for column "$columnName": ${cause.message}', cause);
  }
}

// --- Configuration/Argument Level Exceptions ---

/// Exception for invalid arguments passed to methods.
class InvalidArgumentException extends DoctrineDbalException {
  // Corrected Super Call
  InvalidArgumentException(String message) : super(message);
}

/// Exception for when a required driver option is missing.
class DriverRequired extends InvalidArgumentException {
   DriverRequired() : super('Driver option is required.');
}

/// Exception for when an unknown driver alias is provided.
class UnknownDriver extends InvalidArgumentException {
   UnknownDriver(String alias, List<String> knownAliases)
       : super('Unknown driver alias "$alias". Known aliases: ${knownAliases.join(", ")}');
}

/// Exception for when an invalid driver class is provided.
class InvalidDriverClass extends InvalidArgumentException {
   InvalidDriverClass(String className) : super('Invalid driver class "$className".');
}

/// Exception for when an invalid wrapper class is provided.
class InvalidWrapperClass extends InvalidArgumentException {
   InvalidWrapperClass(String className) : super('Invalid wrapper class "$className".');
}

/// Exception for malformed DSN strings.
class MalformedDsnException extends InvalidArgumentException {
   MalformedDsnException(String dsn, String reason) : super('Malformed DSN "$dsn": $reason');

   factory MalformedDsnException.missingPart(String dsn, String missingPart) {
       return MalformedDsnException(dsn, 'Missing "$missingPart" part.');
   }
}

// --- Other Exceptions ---

/// Exception for when a key=>value array must be provided but is not.
class NoKeyValue extends DoctrineDbalException {
  // Corrected Super Call
  NoKeyValue() : super('A key=>value array must be provided.');
}

/// Marker interface for exceptions that indicate an operation might be safely retried.
abstract class RetryableException implements Exception {}