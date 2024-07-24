class PDOConfig {
  final String driver;
  final String host;
  final int port;
  final String database;
  final String? username;
  final String? password;
  final bool? isUnixSocket;
  /// win1252 | utf8 | utf8mb4_general_ci
  final String? charset;

  /// enable pool ?
  final bool? pool;
  final int? poolSize;
  String? applicationName;
  final bool? allowReconnect;

  /// require | disable
  String? sslmode;
  /// UTC | America/Sao_Paulo
  String? timezone;
  String? schema;

  /// If true, decodes the timestamp with timezone (timestamptz) as UTC.
  /// If false, decodes the timestamp with timezone using the timezone defined in the connection.
  bool forceDecodeTimestamptzAsUTC = true;

  /// If true, decodes the timestamp without timezone (timestamp) as UTC.
  /// If false, decodes the timestamp without timezone as local datetime.
  bool forceDecodeTimestampAsUTC = true;

  /// If true, decodes the date as UTC.
  /// If false, decodes the date as local datetime.
  bool forceDecodeDateAsUTC = true;

  PDOConfig({
    required this.driver,
    required this.host,
    this.port = 5432,
    required this.database,
    this.username,
    this.password,
    this.isUnixSocket = false,
    this.pool = false,
    this.poolSize = 1,
    this.applicationName,
    this.charset = 'utf8',
    this.allowReconnect,
    this.sslmode,
    this.timezone,
    this.schema,
    this.forceDecodeTimestamptzAsUTC = true,
    this.forceDecodeTimestampAsUTC = true,
    this.forceDecodeDateAsUTC = true,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'driver': driver,
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'isUnixSocket': isUnixSocket,
      'charset': charset,
      'pool': pool,
      'poolsize': poolSize,
      'applicationName': applicationName,
      'allowReconnect': allowReconnect,
      'sslmode': sslmode,
      'timezone': timezone,
      'schema': schema,
      'forceDecodeTimestamptzAsUTC': forceDecodeTimestamptzAsUTC,
      'forceDecodeTimestampAsUTC': forceDecodeTimestampAsUTC,
      'forceDecodeDateAsUTC': forceDecodeDateAsUTC,
    };
  }

  factory PDOConfig.fromMap(Map<String, dynamic> map) {
    final config = PDOConfig(
      driver: map['driver'],
      host: map['host'],
      port: map['port'] is int ? map['port'] : int.parse(map['port']),
      database: map['database'],
      username: map['username'],
      password: map['password'],
      isUnixSocket: map['is_unix_socket'],
      charset: map['charset'],
      pool: map['pool'],
      poolSize: map['poolsize'],
      applicationName: map['application_name'],
      allowReconnect: map['allowreconnect'],
      sslmode: map['sslmode'],
      timezone: map['timezone'],
      schema: map['schema'],
    );
    if (map['forceDecodeTimestamptzAsUTC'] is bool) {
      config.forceDecodeTimestamptzAsUTC = map['forceDecodeTimestamptzAsUTC'];
    }
    if (map['forceDecodeTimestampAsUTC'] is bool) {
      config.forceDecodeTimestampAsUTC = map['forceDecodeTimestampAsUTC'];
    }
    if (map['forceDecodeDateAsUTC'] is bool) {
      config.forceDecodeDateAsUTC = map['forceDecodeDateAsUTC'];
    }

    return config;
  }
}
