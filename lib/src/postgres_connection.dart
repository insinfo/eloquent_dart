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

  ///
  /// Get the default query grammar instance.
  ///
  /// @return \Illuminate\Database\Query\Grammars\PostgresGrammar
  ///
  QueryGrammar getDefaultQueryGrammar() {
    //QueryGrammar()
    return withTablePrefix(QueryPostgresGrammar());
  }

  ///
  /// Get the default schema grammar instance.
  ///
  /// @return \Illuminate\Database\Schema\Grammars\PostgresGrammar
  ///
  SchemaGrammar getDefaultSchemaGrammar() {
    return this.withTablePrefix(SchemaPostgresGrammar());
  }

  ///
  /// Get the default post processor instance.
  ///
  /// @return \Illuminate\Database\Query\Processors\PostgresProcessor
  ///
  PostgresProcessor getDefaultPostProcessor() {
    return PostgresProcessor();
  }

  ///
  /// Get the Doctrine DBAL driver.
  ///
  /// @return \Doctrine\DBAL\Driver\PDOPgSql\Driver
  ///
  // dynamic getDoctrineDriver()
  // {
  //     return new DoctrineDriver;
  // }
}
