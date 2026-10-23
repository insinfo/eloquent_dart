import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';

class PostgresConnection extends Connection {
  PostgresConnection(PDOExecutionContext pdoP,
      [String databaseP = '',
      String tablePrefixP = '',
      Map<String, dynamic> configP = const {}])
      : super(pdoP, databaseP, tablePrefixP, configP);

  /// Transaction callbacks get a [PostgresConnection] too.
  @override
  Connection newConnectionForPdo(PDOExecutionContext pdoContext) {
    return PostgresConnection(pdoContext, this.getDatabaseName(),
        this.getTablePrefix(), this.getConfigs());
  }

  /// Returns a [QueryPostgresGrammar] with this connection's table prefix.
  QueryGrammar getDefaultQueryGrammar() {
    //QueryGrammar()
    return withTablePrefix(QueryPostgresGrammar());
  }

  /// Returns a [SchemaPostgresGrammar] with this connection's table prefix.
  SchemaGrammar getDefaultSchemaGrammar() {
    return this.withTablePrefix(SchemaPostgresGrammar());
  }

  /// Returns a [PostgresProcessor].
  PostgresProcessor getDefaultPostProcessor() {
    return PostgresProcessor();
  }
}
