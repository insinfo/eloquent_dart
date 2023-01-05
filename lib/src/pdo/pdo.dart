import 'package:dargres/dargres.dart';
import 'pdo_constants.dart';
import 'pdo_execution_context.dart';
import 'pdo_statement.dart';
import 'package:eloquent/src/utils/dsn_parser.dart';

import 'pdo_transaction.dart';

//enum PDO_ENUMS { PDO_PARAM_STR }
const PDO_PARAM_STR = 2;

/// defines a lightweight, consistent interface for accessing databases
/// provides a data-access abstraction layer
class PDO extends PDOExecutionContext {
  String dsn;
  String user;
  String password;
  String dbname = '';
  int port = 5432;
  String driver = 'pgsql';
  String host = 'localhost';
  dynamic attributes;

  int rowsAffected = 0;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  /// var dsn = "pgsql:host=$host;port=5432;dbname=$db;";
  /// var pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// await pdo.connect();
  ///
  PDO(this.dsn, this.user, this.password, [this.attributes]) {
    //print('PDO@construct');
    super.pdoInstance = this;
  }

  CoreConnection? connection;

  //called from postgres_connector.dart
  Future<PDO> connect() async {
    // var sslContext = SslContext.createDefaultContext();
    //print('PDO@connect dsn: $dsn');
    final parser = DSNParser(dsn, DsnType.pdoPostgreSql);

    connection = CoreConnection(
      user,
      database: parser.database,
      host: parser.host,
      port: parser.port,
      password: password,
      allowAttemptToReconnect: false,
      // sslContext: sslContext,
    );

    await connection!.connect();
    return this;
  }

  /// Inicia uma transação
  /// Retorna true em caso de sucesso ou false em caso de falha.
  Future<PDOTransaction> beginTransaction() async {
    final ctx = await connection!.beginTransaction();
    return PDOTransaction(ctx, this);
  }

  /// Envia uma transação
  Future<void> commit(PDOTransaction transaction) {
    return connection!.commit(transaction.transactionContext);
  }

  /// Rolls back a transaction
  Future<void> rollBack(PDOTransaction transaction) {
    return connection!.rollBack(transaction.transactionContext);
  }

  /// Fetch the SQLSTATE associated with the last operation on the database handle
  // String? errorCode() {
  //   throw UnimplementedError();
  // }

  /// Fetch extended error information associated with the last operation on the database handle
  /// Return array|Map
  // dynamic errorInfo() {
  //   throw UnimplementedError();
  // }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement) {
    // print('PDO@exec statement: $statement');
    // throw UnimplementedError();
    return connection!.execute(statement);
  }

  /// Recuperar um atributo da conexão com o banco de dados
  // dynamic getAttribute() {
  //   throw UnimplementedError();
  // }

  /// Retorna um array com os drivers PDO disponíveis
  // List<String> getAvailableDrivers() {
  //   throw UnimplementedError();
  // }

  /// Checks if inside a transaction
  // bool inTransaction() {
  //   throw UnimplementedError();
  // }

  /// Returns the ID of the last inserted row or sequence value
  /// Return string|false
  // dynamic lastInsertId() {
  //   throw UnimplementedError();
  // }

  /// Prepares a statement for execution and returns a statement object
  /// Return PDOStatement
  /// Prepares an SQL statement to be executed by the PDOStatement::execute() method.
  /// The statement template can contain zero or more named (:name) or question mark (?) parameter
  ///  markers for which real values will be substituted when the statement is executed.
  /// Both named and question mark parameter markers cannot be used within the same
  /// statement template; only one or the other parameter style.
  /// Use these parameters to bind any user-input, do not include
  /// the user-input directly in the query.
  ///
  /// You must include a unique parameter marker for each value you wish to
  /// pass in to the statement when you call PDOStatement::execute().
  ///  You cannot use a named parameter marker of the same name more
  /// than once in a prepared statement, unless emulation mode is on.
  /// Nota:
  /// Parameter markers can represent a complete data literal only.
  /// Neither part of literal, nor keyword, nor identifier, nor
  /// whatever arbitrary query part can be bound using parameters.
  /// For example, you cannot bind multiple values to a single
  /// parameter in the IN() clause of an SQL statement.
  ///
  /// Calling PDO::prepare() and PDOStatement::execute() for statements that
  /// will be issued multiple times with different parameter values optimizes
  ///  the performance of your application by allowing the driver to
  /// negotiate client and/or server side caching of the query plan
  /// and meta information. Also, calling PDO::prepare() and PDOStatement::execute()
  /// helps to prevent SQL injection attacks by eliminating the need to
  /// manually quote and escape the parameters.
  Future<PDOStatement> prepareStatement(String query, dynamic params) async {
    final postgresQuery = await connection!.prepareStatement(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
    return PDOStatement(postgresQuery);
  }

  Future<dynamic> executeStatement(PDOStatement statement,
      [int? fetchMode]) async {
    var results = await connection!.executeStatement(statement.postgresQuery!);
    statement.rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  Future<dynamic> queryUnnamed(String query, dynamic params,
      [int? fetchMode]) async {
    var results = await connection!.queryUnnamed(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);        
    rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<dynamic> query(String query, [int? fetchMode]) async {
    var results = await connection!.queryUnnamed(query, []);
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  /// Quotes a string for use in a query
  /// Return string|false
  // dynamic quote(String string, [int type = PDO_PARAM_STR]) {
  //   throw UnimplementedError();
  // }

  ///  Set an attribute
  // bool setAttribute(int attribute, dynamic value) {
  //   throw UnimplementedError();
  // }
}
