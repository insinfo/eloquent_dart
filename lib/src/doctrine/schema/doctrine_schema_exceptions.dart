
//lib\src\doctrine\exceptions\doctrine_schema_exceptions.dart

class DoctrineSchemaException implements Exception {
  final String message;
  DoctrineSchemaException(this.message);
  @override
  String toString() => 'DoctrineSchemaException: $message';
}

class TableAlreadyExistsException extends DoctrineSchemaException {
  TableAlreadyExistsException(String tableName) : super('Table "$tableName" already exists.');
}

class TableDoesNotExistException extends DoctrineSchemaException {
  TableDoesNotExistException(String tableName) : super('Table "$tableName" does not exist.');
}

class SequenceAlreadyExistsException extends DoctrineSchemaException {
  SequenceAlreadyExistsException(String sequenceName) : super('Sequence "$sequenceName" already exists.');
}

class SequenceDoesNotExistException extends DoctrineSchemaException {
  SequenceDoesNotExistException(String sequenceName) : super('Sequence "$sequenceName" does not exist.');
}

class NamespaceAlreadyExistsException extends DoctrineSchemaException {
  NamespaceAlreadyExistsException(String namespaceName) : super('Namespace "$namespaceName" already exists.');
}