import 'package:eloquent/eloquent.dart';

class PostgresConnector extends Connector implements ConnectorInterface {
  ///
  /// The default PDO connection options.
  ///
  /// @var array
  ///
  Map<String, dynamic> options = {};

  ///
  /// Establish a database connection.
  ///
  /// [config] Map<String, dynamic>
  /// @return PostgreSQLConnection \PDO
  ///
  Future<PDO> connect(Map<String, dynamic> config) async{
    // First we'll create the basic DSN and connection instance connecting to the
    // using the configuration option specified by the developer. We will also
    // set the default character set on the connections to UTF-8 by default.
    var dsn = getDsn(config);

    var options = getOptions(config);

    var connection = await createConnection(dsn, config, options);

    if (config.containsKey('charset') && config['charset'] != null) {
      var charset = config['charset'];
   await   connection.execute("set names '$charset'");
    }

    // Next, we will check to see if a timezone has been specified in this config
    // and if it has we will issue a statement to modify the timezone with the
    // database. Setting this DB timezone is an optional configuration item.

    if (config.containsKey('timezone') && config['timezone'] != null) {
      var timezone = config['timezone'];
    await  connection.execute("set time zone '$timezone'");
    }

    // Unlike MySQL, Postgres allows the concept of "schema" and a default schema
    // may have been specified on the connections. If that is the case we will
    // set the default schema search paths to the specified database schema.
    if (config.containsKey('schema') && config['schema'] != null) {
      var schema = formatSchema(config['schema']);

    await  connection.execute("set search_path to $schema");
    }

    // Postgres allows an application_name to be set by the user and this name is
    // used to when monitoring the application with pg_stat_activity. So we'll
    // determine if the option has been specified and run a statement if so.

    if (config.containsKey('application_name') &&
        config['application_name'] != null) {
      var applicationName = config['application_name'];
     await connection.execute("set application_name to '$applicationName'");
    }

    return connection;
  }

  ///
  /// Create a DSN string from a configuration.
  ///
  /// @param  array   $config
  /// @return string
  ///
  String getDsn(Map<String, dynamic> config) {
    // First we will create the basic DSN setup as well as the port if it is in
    // in the configuration options. This will give us the basic DSN we will
    // need to establish the PDO connections and return them back for use.

    var host = config['host'] != null ? "host=${config['host']};" : '';
    var dsn = "pgsql:${host}dbname=${config['database']}";

    // If a port was specified, we will add it to this Postgres DSN connections
    // format. Once we have done that we are ready to return this connection
    // string back out for usage, as this has been fully constructed here.
    if (config['port'] != null) {
      dsn += ";port=${config['port']}";
    }

    if (config['sslmode'] != null) {
      dsn += ";sslmode=${config['sslmode']}";
    }

    return dsn;
  }

  ///
  /// Format the schema for the DSN.
  ///
  /// @param  array|string  $schema
  /// @return string
  ///
  String formatSchema(dynamic schema) {
    if (Utils.is_array(schema)) {
      return '"' + Utils.implode('", "', schema) + '"';
    } else {
      return '"' + schema + '"';
    }
  }

  ///
  /// Create a new PDO connection.
  ///
  /// @param  string  $dsn
  /// @param  array   $config
  /// @param  array   $options
  /// @return \PDO
  /// Aqui que cria a conexão com o Banco de Dados de fato
  ///
 Future<PDO> createConnection(
      String dsn, Map<String, dynamic> config, Map<String, dynamic> options) async{
    var username = config['username'];
    var password = config['password'];
    // var host = config['host'];
    // var port = config['port']; //5432
    // var database = config['database'];
    // try {
    //     $pdo = new PDO($dsn, $username, $password, $options);
    // } catch (Exception e) {
    //     $pdo = $this->tryAgainIfCausedByLostConnection(
    //         $e, $dsn, $username, $password, $options
    //     );
    // }

    var pdo = new PDO(dsn, username, password, options);
    await pdo.connect();

    return pdo;
  }
}
