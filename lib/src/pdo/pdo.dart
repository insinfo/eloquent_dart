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
  /// default query Timeout =  300 seconds
  static const defaultTimeout = const Duration(seconds: 300);

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
  /// Example: "pgsql:host=$host;dbname=$db;charset=utf8";
  /// var pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// await pdo.connect();
  ///
  PDO(this.dsn, this.user, this.password, [this.attributes]) {
    //print('PDO@construct');
    super.pdoInstance = this;
  }

  /// CoreConnection
  ExecutionContext? connection;

  //called from postgres_connector.dart
  Future<PDO> connect() async {
    // var sslContext = SslContext.createDefaultContext();
    //print('PDO@connect dsn: $dsn');
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);
    //print( 'PDO@connect parser.pool: ${dsnParser.pool} poolSize: ${dsnParser.poolSize} allowReconnect: ${dsnParser.allowReconnect} applicationName: ${dsnParser.applicationName}');

    if (dsnParser.pool == true) {
      final settings = ConnectionSettings(
        user: user,
        database: dsnParser.database,
        host: dsnParser.host,
        port: dsnParser.port,
        password: password,
        textCharset: dsnParser.charset,
        applicationName: dsnParser.applicationName,
        allowAttemptToReconnect: false,
      );
      connection = PostgreSqlPool(dsnParser.poolSize, settings,
          allowAttemptToReconnect: dsnParser.allowReconnect);
    } else {
      connection = CoreConnection(user,
          database: dsnParser.database,
          host: dsnParser.host,
          port: dsnParser.port,
          password: password,
          allowAttemptToReconnect: false,
          // sslContext: sslContext,
          textCharset: dsnParser.charset);
      await connection!.connect();
      // final conn = CoreConnection.fromSettings(settings);
    }

    return this;
  }

  /// Inicia uma transação
  /// Retorna true em caso de sucesso ou false em caso de falha.
  // Future<PDOTransaction> beginTransaction() async {
  //   final ctx = await connection!.beginTransaction();
  //   return PDOTransaction(ctx, this);
  // }

  // /// Envia uma transação
  // Future<void> commit(PDOTransaction transaction) {
  //   return connection!.commit(transaction.transactionContext);
  // }

  // /// Rolls back a transaction
  // Future<void> rollBack(PDOTransaction transaction) {
  //   return connection!.rollBack(transaction.transactionContext);
  // }

  Future<T> runInTransaction<T>(
    Future<T> operation(PDOTransaction ctx), {
    Duration? timeout = defaultTimeout,
    Duration? timeoutInner = defaultTimeout,
  }) async {
    return await connection!.runInTransaction((ctx) async {
      final pdoCtx = PDOTransaction(ctx, this);
      return await operation(pdoCtx);
    }, timeout: timeout, timeoutInner: timeoutInner);
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [Duration? timeout = defaultTimeout]) {
    // print('PDO@exec statement: $statement');
    // throw UnimplementedError();
    return connection!.execute(statement, timeout: timeout);
  }

  /// Recuperar um atributo da conexão com o banco de dados
  // dynamic getAttribute() {
  //   throw UnimplementedError();
  // }

  /// Retorna um array com os drivers PDO disponíveis
  List<String> getAvailableDrivers() {
    throw UnimplementedError();
  }

  /// Checks if inside a transaction
  // bool inTransaction() {
  //   throw UnimplementedError();
  // }

  /// Returns the ID of the last inserted row or sequence value
  /// Return string|false
  dynamic lastInsertId() {
    throw UnimplementedError();
  }

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
  Future<PDOStatement> prepareStatement(String query, dynamic params,
      [Duration? timeout = defaultTimeout]) async {
    final postgresQuery = await connection!.prepareStatement(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);
    return PDOStatement(postgresQuery);
  }

  Future<dynamic> executeStatement(PDOStatement statement,
      [int? fetchMode, Duration? timeout = defaultTimeout]) async {
    var results = await connection!
        .executeStatement(statement.postgresQuery!, timeout: timeout);
    statement.rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  Future<dynamic> queryNamed(String query, dynamic params,
      [int? fetchMode, Duration? timeout = defaultTimeout]) async {
    //print('PDO@queryNamed timeout $timeout');
    var results = await connection!.queryNamed(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);

    rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  Future<dynamic> queryUnnamed(String query, dynamic params,
      [int? fetchMode, Duration? timeout = defaultTimeout]) async {
    // print('PDO@queryNamed timeout $timeout');
    var results = await connection!.queryUnnamed(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);

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
  Future<dynamic> query(String query,
      [int? fetchMode, Duration? timeout = defaultTimeout]) async {
    var results = await connection!.queryNamed(query, [], timeout: timeout);
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
