import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/mysql_processor.dart';

import 'query/grammars/query_mysql_grammar.dart';
import 'schema/grammars/schema_mysql_grammar.dart';

class MySqlConnection extends Connection {
  MySqlConnection(PDOExecutionContext pdoP,
      [String databaseP = '',
      String tablePrefixP = '',
      Map<String, dynamic> configP = const {}])
      : super(pdoP, databaseP, tablePrefixP, configP);

 
  /// Execute a Closure within a transaction.
  ///
  /// @param  Function  callback
  /// @return mixed
  ///
  /// @throws \Throwable
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) async {
    var result = this.pdo.pdoInstance.runInTransaction((pdoCtx) {
      final newConnection = MySqlConnection(pdoCtx, this.getDatabaseName(),
          this.getTablePrefix(), this.getConfigs());
      return callback(newConnection);
    });

    return result;
  }

  ///
  /// Get the default query grammar instance.
  ///
  /// @return \Illuminate\Database\Query\Grammars\QueryMySqlGrammar
  ///
  QueryGrammar getDefaultQueryGrammar() {  
    return withTablePrefix(QueryMySqlGrammar());
  }

  ///
  /// Get the default schema grammar instance.
  ///
  /// @return \Illuminate\Database\Schema\Grammars\SchemaMySqlGrammar
  ///
  SchemaGrammar getDefaultSchemaGrammar() {
    return this.withTablePrefix(SchemaMySqlGrammar());
  }

  ///
  /// Get the default post processor instance.
  ///
  /// @return \Illuminate\Database\Query\Processors\MySqlProcessor
  ///
  MySqlProcessor getDefaultPostProcessor() {
    return MySqlProcessor();
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
