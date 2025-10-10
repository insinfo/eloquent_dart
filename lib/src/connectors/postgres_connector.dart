import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/pdo/dargres/dargres_pdo.dart';
import 'package:eloquent/src/pdo/postgres/postgres_pdo.dart';
import 'package:eloquent/src/pdo/postgres_v3/postgres_v3_pdo.dart';

class PostgresConnector extends Connector implements ConnectorInterface {
  ///
  /// The default PDO connection options.
  ///
  /// @var array
  ///
  Map<dynamic, dynamic> options = {};

  ///
  /// Establish a database connection.
  ///
  /// [config] Map<String, dynamic>
  /// @return PostgreSQLConnection \PDO
  ///
  Future<PDOInterface> connect(Map<String, dynamic> config) async {
    // First we'll create the basic DSN and connection instance connecting to the
    // using the configuration option specified by the developer. We will also
    // set the default character set on the connections to UTF-8 by default.

    //var dsn = getDsn(config);
    //var options = getOptions(config);
    final connection = await createConnection(config);

    // if (config.containsKey('charset') && config['charset'] != null) {
    //   var charset = config['charset'];
    //   //await connection.execute("set names '$charset'");
    // }

    // Next, we will check to see if a timezone has been specified in this config
    // and if it has we will issue a statement to modify the timezone with the
    // database. Setting this DB timezone is an optional configuration item.

    // if (config.containsKey('timezone') && config['timezone'] != null) {
    //   var timezone = config['timezone'];
    //   await connection.execute("set timezone TO '$timezone'");
    // }

    // Unlike MySQL, Postgres allows the concept of "schema" and a default schema
    // may have been specified on the connections. If that is the case we will
    // set the default schema search paths to the specified database schema.
    // if (config.containsKey('schema') && config['schema'] != null) {
    //   var schema = formatSchema(config['schema']);
    //   await connection.execute("set search_path to $schema");
    // }

    // Postgres allows an application_name to be set by the user and this name is
    // used to when monitoring the application with pg_stat_activity. So we'll
    // determine if the option has been specified and run a statement if so.

    // if (config.containsKey('application_name') &&
    //     config['application_name'] != null) {
    //   var applicationName = config['application_name'];
    //   try {
    //     await connection.execute("set application_name to '$applicationName'");
    //   } catch (e) {
    //     print(
    //         'Eloquent: Unable to set the application_name for this PostgreSQL driver.');
    //   }
    // }

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

    if (config['schema'] != null) {
      dsn += ";schema=${formatSchema(config['schema'])}";
    }

    if (config['timezone'] != null) {
      dsn += ";timezone=${config['timezone']}";
    }

    return dsn;
  }

  /// Converte o parâmetro `schema` (String ou List<String>) no formato
  /// `"esquema1","esquema2"` aceito pelo comando
  /// `SET search_path TO …`.
  ///
  /// *  Aceita `null`, string vazia ou itens vazios no meio da lista
  ///    – eles são simplesmente ignorados.
  /// *  Mantém itens que **já** estejam entre aspas duplas, sem duplicá-las.
  /// *  Remove espaços em volta de cada nome.
  /// *  Elimina esquemas duplicados, preservando a primeira ocorrência.
  ///
  String formatSchema(dynamic schema) {
    // 1. Quebra em partes
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

    // 2. Normaliza, filtra vazios, evita duplicatas
    final seen = <String>{};
    final buffer = StringBuffer();
    for (var raw in parts) {
      var s = raw.trim();
      if (s.isEmpty) continue;

      // já está entre aspas? mantém
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

  ///
  /// Create a new PDO connection.
  ///
  /// @param  string  $dsn
  /// @param  array   $config
  /// @param  array   $options
  /// @return \PDO
  /// Aqui que cria a conexão com o Banco de Dados de fato
  ///
  Future<PDOInterface> createConnection(Map<String, dynamic> conf) async {
    // clone – evita side-effects entre requisições
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
      default:
        pdo = PostgresV2PDO(pdoConfig);
    }
    await pdo.connect();
    return pdo;
  }
}
