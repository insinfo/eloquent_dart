//enum PDO_ENUMS { PDO_PARAM_STR }

const PDO_PARAM_STR = 2;

class PDO {
  String dsn;
  String user;
  String password;
  String dbname = '';
  int port = 5432;
  String driver = 'pgsql';
  String host = 'localhost';
  dynamic attributes;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  /// $dsn = "pgsql:host=$host;port=5432;dbname=$db;";
  /// $pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// if ($pdo) {
  /// 	echo "Connected to the $db database successfully!";
  /// }
  ///
  PDO(this.dsn, this.user, this.password, [this.attributes]) {}

  /// Inicia uma transação
  /// Retorna true em caso de sucesso ou false em caso de falha.
  bool beginTransaction() {
    throw UnimplementedError();
  }

  /// Envia uma transação
  bool commit() {
    throw UnimplementedError();
  }

  /// Fetch the SQLSTATE associated with the last operation on the database handle
  String? errorCode() {
    throw UnimplementedError();
  }

  /// Fetch extended error information associated with the last operation on the database handle
  /// Return array|Map
  dynamic errorInfo() {
    throw UnimplementedError();
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  int exec(String statement) {
    print('PDO@exec statement: $statement');
    //throw UnimplementedError();
    return 1;
  }

  /// Recuperar um atributo da conexão com o banco de dados
  dynamic getAttribute() {
    throw UnimplementedError();
  }

  /// Retorna um array com os drivers PDO disponíveis
  List<String> getAvailableDrivers() {
    throw UnimplementedError();
  }

  /// Checks if inside a transaction
  bool inTransaction() {
    throw UnimplementedError();
  }

  /// Returns the ID of the last inserted row or sequence value
  /// Return string|false
  dynamic lastInsertId() {
    throw UnimplementedError();
  }

  /// Prepares a statement for execution and returns a statement object
  /// Return PDOStatement|false
  dynamic prepare(String query, [List options = const []]) {
    print('PDO@prepare query: $query');
    throw UnimplementedError();
  }

  /// Prepares and executes an SQL statement without placeholders
  /// Return PDOStatement|false
  dynamic query(String query, [int? fetchMode]) {
    throw UnimplementedError();
  }

  /// Quotes a string for use in a query
  /// Return string|false
  dynamic quote(String string, [int type = PDO_PARAM_STR]) {
    throw UnimplementedError();
  }

  /// Rolls back a transaction
  bool rollBack() {
    throw UnimplementedError();
  }

  ///  Set an attribute
  bool setAttribute(int attribute, dynamic value) {
    throw UnimplementedError();
  }
}
