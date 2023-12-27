import 'package:eloquent/eloquent.dart';

import 'package:eloquent/src/pdo/mysql_client/mysql_client_pdo.dart';

class MySqlConnector extends Connector implements ConnectorInterface {
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
  Future<PDOInterface> connect(Map<String, dynamic> config) async {
    final dsn = getDsn(config);
    final options = getOptions(config);

    final connection = await createConnection(dsn, config, options);

    if (config.containsKey('database') && config['database'] != null) {
      await connection.execute("use `${config['database']}`;");
    }

    // var collation =config.containsKey('collation') ? config['collation'] : null;

    // Next we will set the "names" and "collation" on the clients connections so
    // a correct character set will be used by this client. The collation also
    // is set on the server but needs to be set here on this client objects.

    if (config.containsKey('charset') && config['charset'] != null) {
      var charset = config['charset'];

      var names = "set names '$charset'" +
          (config.containsKey('collation')
              ? " collate '${config['collation']}'"
              : '');

      await connection.execute(names);
    }
    // Next, we will check to see if a timezone has been specified in this config
    // and if it has we will issue a statement to modify the timezone with the
    // database. Setting this DB timezone is an optional configuration item.
    if (config.containsKey('timezone')) {
      await connection.execute('set time_zone="' + config['timezone'] + '"');
    }

    await this.setModes(connection, config);

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

    final host = config['host'] != null ? "host=${config['host']};" : '';
    var dsn = "mysql:${host}dbname=${config['database']}";

    // If a port was specified, we will add it to this Postgres DSN connections
    // format. Once we have done that we are ready to return this connection
    // string back out for usage, as this has been fully constructed here.
    if (config['port'] != null) {
      dsn += ";port=${config['port']}";
    }

    if (config['sslmode'] != null) {
      dsn += ";sslmode=${config['sslmode']}";
    }

    // add charset to DSN
    if (config.containsKey('charset') && config['charset'] != null) {
      dsn = "$dsn;charset=${config['charset']}";
    }
    // add Pool opttions to DSN
    if (config['pool'] != null) {
      dsn += ";pool=${config['pool']}";
    }

    if (config['poolsize'] != null) {
      dsn += ";poolsize=${config['poolsize']}";
    }

    if (config['allowreconnect'] != null) {
      dsn += ";allowreconnect=${config['allowreconnect']}";
    }

    if (config['application_name'] != null) {
      dsn += ";application_name=${config['application_name']}";
    }

    return dsn;
  }

  ///
  /// Set the modes for the connection.
  ///
  /// @param  \PDO  $connection
  /// @param  array  $config
  /// @return void
  ///
  Future<void> setModes(
      PDOInterface connection, Map<String, dynamic> config) async {
    if (config.containsKey('modes')) {
      var modes = Utils.implode(',', config['modes']);

      connection.execute("set session sql_mode='" + modes + "'");
    } else if (config.containsKey('strict')) {
      if (config['strict'] != null) {
        await connection.execute(
            "set session sql_mode='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'");
      } else {
        await connection
            .execute("set session sql_mode='NO_ENGINE_SUBSTITUTION'");
      }
    }
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
  Future<PDOInterface> createConnection(String dsn, Map<String, dynamic> config,
      Map<String, dynamic> options) async {
    final username = config['username'];
    final password = config['password'];

    late PDOInterface pdo;

    // if (config['driver_implementation'] == 'postgres') {
    //   pdo = MySqlClientPDO(dsn, username, password, options);


    pdo = MySqlClientPDO(dsn, username, password);

    await pdo.connect();

    return pdo;
  }
}
