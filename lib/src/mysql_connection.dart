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

  /// Transaction callbacks get a [MySqlConnection] too.
  @override
  Connection newConnectionForPdo(PDOExecutionContext pdoContext) {
    return MySqlConnection(pdoContext, this.getDatabaseName(),
        this.getTablePrefix(), this.getConfigs());
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
