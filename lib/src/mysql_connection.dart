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

  /// Returns a [QueryMySqlGrammar] with this connection's table prefix.
  QueryGrammar getDefaultQueryGrammar() {
    return withTablePrefix(QueryMySqlGrammar());
  }

  /// Returns a [SchemaMySqlGrammar] with this connection's table prefix.
  SchemaGrammar getDefaultSchemaGrammar() {
    return this.withTablePrefix(SchemaMySqlGrammar());
  }

  /// Returns a [MySqlProcessor].
  MySqlProcessor getDefaultPostProcessor() {
    return MySqlProcessor();
  }
}
