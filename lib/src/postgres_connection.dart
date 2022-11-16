import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';

class PostgresConnection extends Connection {
  PostgresConnection(PDO pdoP,
      [String databaseP = '',
      String tablePrefixP = '',
      Map<String, dynamic> configP = const {}])
      : super(pdoP, databaseP, tablePrefixP, configP) {}

  ///
  /// Get the default query grammar instance.
  ///
  /// @return \Illuminate\Database\Query\Grammars\PostgresGrammar
  ///
  QueryGrammar getDefaultQueryGrammar() {
    return withTablePrefix(QueryGrammar());
  }

  ///
  /// Get the default schema grammar instance.
  ///
  /// @return \Illuminate\Database\Schema\Grammars\PostgresGrammar
  ///
  SchemaGrammar getDefaultSchemaGrammar() {
    return this.withTablePrefix(SchemaGrammar());
  }

  ///
  /// Get the default post processor instance.
  ///
  /// @return \Illuminate\Database\Query\Processors\PostgresProcessor
  ///
  PostgresProcessor getDefaultPostProcessor() {
    return new PostgresProcessor();
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
