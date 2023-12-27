import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';

class PostgresConnection extends Connection {
  PostgresConnection(PDOExecutionContext pdoP,
      [String databaseP = '',
      String tablePrefixP = '',
      Map<String, dynamic> configP = const {}])
      : super(pdoP, databaseP, tablePrefixP, configP);

  ///
  /// Execute a Closure within a transaction.
  ///
  /// @param  Function  callback
  /// @return mixed
  ///
  /// @throws \Throwable
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) async {
    var result = this.pdo.pdoInstance.runInTransaction((pdoCtx) {
      final newConnection = PostgresConnection(pdoCtx, this.getDatabaseName(),
          this.getTablePrefix(), this.getConfigs());
      return callback(newConnection);
    });

    return result;
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
