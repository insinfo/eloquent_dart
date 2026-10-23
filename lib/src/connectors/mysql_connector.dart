import 'package:eloquent/eloquent.dart';

import 'package:eloquent/src/pdo/mysql_client/mysql_client_pdo.dart';

class MySqlConnector extends Connector implements ConnectorInterface {
  /// The default connection options.
  Map<dynamic, dynamic> options = {};

  /// Opens a MySQL connection with the settings in [config].
  Future<PDOInterface> connect(Map<String, dynamic> config) async {
    // The session statements run on every physical connection (each pool
    // connection and reconnects), not once on whichever connection the pool
    // happened to hand out. The database is selected in the handshake.
    return createConnection(config);
  }

  /// Session statements for a new physical connection: character set,
  /// time zone and SQL modes.
  List<String> sessionStatements(Map<String, dynamic> config) {
    final statements = <String>[];

    // Next we will set the "names" and "collation" on the client's connections
    // so a correct character set will be used by this client.
    if (config.containsKey('charset') && config['charset'] != null) {
      var charset = config['charset'];

      statements.add("set names '$charset'" +
          (config.containsKey('collation')
              ? " collate '${config['collation']}'"
              : ''));
    }
    // Setting this DB timezone is an optional configuration item.
    if (config.containsKey('timezone') && config['timezone'] != null) {
      statements.add('set time_zone="' + config['timezone'] + '"');
    }

    final mode = this.sqlModeStatement(config);
    if (mode != null) statements.add(mode);

    return statements;
  }

  /// Builds a DSN string (`mysql:host=...;dbname=...`) from [config].
  String getDsn(Map<String, dynamic> config) {
    // First we will create the basic DSN setup as well as the port if it is in
    // in the configuration options. This will give us the basic DSN we will
    // need to establish the PDO connections and return them back for use.

    final host = config['host'] != null ? "host=${config['host']};" : '';
    var dsn = "mysql:${host}dbname=${config['database']}";

    // If a port was specified, we will add it to this MySQL DSN connections
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
    // add pool options to DSN
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

  /// Runs the [sqlModeStatement] for [config] on [connection], if there is
  /// one.
  Future<void> setModes(
      PDOInterface connection, Map<String, dynamic> config) async {
    final mode = this.sqlModeStatement(config);
    if (mode != null) await connection.execute(mode);
  }

  /// The `set session sql_mode` statement for [config], if any.
  String? sqlModeStatement(Map<String, dynamic> config) {
    if (config.containsKey('modes')) {
      var modes = Utils.implode(',', config['modes']);
      return "set session sql_mode='" + modes + "'";
    } else if (config.containsKey('strict')) {
      if (config['strict'] != null) {
        return "set session sql_mode='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'";
      }
      return "set session sql_mode='NO_ENGINE_SUBSTITUTION'";
    }
    return null;
  }

  /// Wraps [schema], a name or a list of names, in double quotes for the
  /// DSN; list items are joined with `, `.
  String formatSchema(dynamic schema) {
    if (Utils.is_array(schema)) {
      return '"' + Utils.implode('", "', schema) + '"';
    } else {
      return '"' + schema + '"';
    }
  }

  /// Opens a [MySqlClientPDO] connection with the settings in [config].
  ///
  /// The [sessionStatements] run on every new physical connection.
  Future<PDOInterface> createConnection(Map<String, dynamic> config) async {
    late PDOInterface pdo;

    final pdoConfig = PDOConfig.fromMap(config);

    pdo = MySqlClientPDO(pdoConfig,
        sessionStatements: this.sessionStatements(config));

    await pdo.connect();

    return pdo;
  }
}
