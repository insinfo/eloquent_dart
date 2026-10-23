import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/pdo/dargres/dargres_pdo.dart';
import 'package:eloquent/src/pdo/dpgsql/dpgsql_pdo.dart';
import 'package:eloquent/src/pdo/postgres/postgres_pdo.dart';
import 'package:eloquent/src/pdo/postgres_v3/postgres_v3_pdo.dart';

class PostgresConnector extends Connector implements ConnectorInterface {
  /// The default connection options.
  Map<dynamic, dynamic> options = {};

  /// Opens a PostgreSQL connection with the settings in [config].
  Future<PDOInterface> connect(Map<String, dynamic> config) async {
    // The charset, time zone, schema (search path) and application name are
    // not set here: they go to the driver in the PDOConfig, and the PDO
    // implementation applies them to its connections.
    final connection = await createConnection(config);

    return connection;
  }

  /// Builds a DSN string (`pgsql:host=...;dbname=...`) from [config].
  String getDsn(Map<String, dynamic> config) {
    // First we will create the basic DSN setup as well as the port if it is in
    // in the configuration options. This will give us the basic DSN we will
    // need to establish the PDO connections and return them back for use.

    final host = config['host'] != null ? "host=${config['host']};" : '';
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

    if (config['schema'] != null) {
      dsn += ";schema=${formatSchema(config['schema'])}";
    }

    if (config['timezone'] != null) {
      dsn += ";timezone=${config['timezone']}";
    }

    return dsn;
  }

  /// Formats [schema] as the `"schema1","schema2"` list that
  /// `SET search_path TO ...` accepts.
  ///
  /// [schema] is a comma-separated `String` or a list of strings; `null`
  /// returns `''` and any other type throws [ArgumentError].
  ///
  /// - Empty names are skipped.
  /// - Names are trimmed; names already in double quotes are kept as they
  ///   are, the others are quoted.
  /// - Duplicates are dropped, keeping the first occurrence.
  String formatSchema(dynamic schema) {
    // 1. Split into names.
    final List<String> parts;
    if (schema is String) {
      parts = schema.split(',');
    } else if (schema is Iterable) {
      parts = schema.cast<String>().toList();
    } else if (schema == null) {
      return '';
    } else {
      throw ArgumentError('schema deve ser String ou List<String>');
    }

    // 2. Normalize, skip empty names, drop duplicates.
    final seen = <String>{};
    final buffer = StringBuffer();
    for (var raw in parts) {
      var s = raw.trim();
      if (s.isEmpty) continue;

      // Already quoted? Keep it.
      if (!(s.startsWith('"') && s.endsWith('"'))) {
        s = '"$s"';
      }

      if (seen.add(s)) {
        if (buffer.isNotEmpty) buffer.write(',');
        buffer.write(s);
      }
    }

    return buffer.toString();
  }

  /// Opens the driver connection with the settings in [conf].
  ///
  /// The `driver_implementation` key picks the driver: `postgres` (the
  /// default), `postgres_v3`, `dargres` or `dpgsql`. A `schema` key is
  /// formatted with [formatSchema].
  Future<PDOInterface> createConnection(Map<String, dynamic> conf) async {
    // A copy, so formatting the schema does not change the caller's map.
    final config = Map<String, dynamic>.from(conf);

    if (config.containsKey('schema')) {
      config['schema'] = formatSchema(config['schema']);
    }

    final pdoConfig = PDOConfig.fromMap(config);
    late PDOInterface pdo;

    switch (conf['driver_implementation']) {
      case 'postgres':
        pdo = PostgresV2PDO(pdoConfig);
        break;
      case 'postgres_v3':
        pdo = PostgresV3PDO(pdoConfig);
        break;
      case 'dargres':
        pdo = DargresPDO(pdoConfig);
        break;
      case 'dpgsql':
        pdo = DpgsqlPDO(pdoConfig);
        break;
      default:
        pdo = PostgresV2PDO(pdoConfig);
    }
    await pdo.connect();
    return pdo;
  }
}
