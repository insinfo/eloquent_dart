import 'dart:io';

/// The `sslmode` config key, with libpq's meaning.
enum PDOSslMode {
  /// Plain connection (also when `sslmode` is absent).
  disable,

  /// TLS when the server accepts it, plain otherwise. Handled as [prefer]:
  /// TLS is tried first.
  allow,

  /// TLS when the server accepts it, plain otherwise. The certificate is
  /// not verified.
  prefer,

  /// TLS or no connection. The certificate is not verified.
  require,

  /// TLS with a certificate signed by a trusted CA. The drivers built on
  /// dart:io cannot skip the host name check, so this is [verifyFull].
  verifyCa,

  /// TLS with a certificate signed by a trusted CA and issued for the host.
  verifyFull,
}

/// How DateTime bindings are sent (`datetime_bindings` config key).
enum DateTimeBindings {
  /// Formatted with the grammar date format (`yyyy-MM-dd HH:mm:ss`) before
  /// reaching the driver, as in Laravel. Drops microseconds and the time zone.
  string,

  /// Passed to the driver as DateTime: microseconds are kept and, on
  /// PostgreSQL, a `timestamptz` column receives the right instant for UTC
  /// and local values.
  native,
}

/// How PostgreSQL values are returned (`pg_types` config key).
enum PgTypes {
  /// The same Dart types on every PostgreSQL adapter: natural types (int,
  /// double, bool, String, DateTime in UTC, Uint8List, Map/List from JSON,
  /// typed lists) as Dart values; numeric as its exact text; the types
  /// without a natural Dart type (interval, time, timetz, inet, cidr,
  /// macaddr, geometric types, bit strings, tsvector, ranges, enums) as the
  /// text the server prints for them, arrays of them as lists of texts, and
  /// arrays of user-defined types as the array literal (`'{ok,sad}'`); money
  /// as the decimal amount (`'12.34'`).
  uniform,

  /// Each driver's own types (PgInterval, DpgsqlRange, Interval...).
  driver,
}

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

  /// disable | allow | prefer | require | verify-ca | verify-full (see
  /// [PDOSslMode] and [parseSslMode]).
  String? sslmode;

  /// [sslmode] parsed; throws [ArgumentError] for an unknown value.
  PDOSslMode get parsedSslMode => parseSslMode(sslmode);

  /// MySQL: the collation of the connection (`collation` config key).
  String? collation;

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

  /// `datetime_bindings`: `'string'` (default) or `'native'`.
  DateTimeBindings dateTimeBindings = DateTimeBindings.string;

  /// `pg_types`: `'uniform'` (default) or `'driver'`.
  PgTypes pgTypes = PgTypes.uniform;

  /// `pg_types: 'uniform'` (the default).
  bool get uniformPgTypes => pgTypes == PgTypes.uniform;

  /// `driver_options`: settings passed to the driver as they are; the keys
  /// each adapter accepts are listed in its error for an unknown key.
  Map<String, dynamic> driverOptions = const {};

  //
  String? statementTimeout;
  String? lockTimeout;
  String? idleInTransactionSessionTimeout;

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
    //new
    this.statementTimeout,
    this.lockTimeout,
    this.idleInTransactionSessionTimeout,
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
      'collation': collation,
      'timezone': timezone,
      'schema': schema,
      'datetime_bindings': dateTimeBindings.name,
      'pg_types': pgTypes.name,
      'driver_options': driverOptions,
      'forceDecodeTimestamptzAsUTC': forceDecodeTimestamptzAsUTC,
      'forceDecodeTimestampAsUTC': forceDecodeTimestampAsUTC,
      'forceDecodeDateAsUTC': forceDecodeDateAsUTC,
//
      'statementTimeout': statementTimeout,
      'lockTimeout': lockTimeout,
      'idleInTransactionSessionTimeout': idleInTransactionSessionTimeout,
    };
  }

  factory PDOConfig.fromMap(Map<String, dynamic> map) {
    // snake_case and camelCase spellings: toMap() wrote `applicationName`,
    // `isUnixSocket`, `allowReconnect` and `poolsize`, which fromMap() did
    // not read back.
    dynamic key(List<String> names) {
      for (final name in names) {
        if (map.containsKey(name)) return map[name];
      }
      return null;
    }

    // A missing key keeps the constructor default instead of passing null.
    // charset is the exception: it has no default here, because the MySQL
    // adapter falls back to its own collation when it is null.
    final sslmode = map['sslmode']?.toString();
    parseSslMode(sslmode);
    final co = PDOConfig(
      driver: map['driver'] as String,
      host: map['host'] as String,
      port: _port(map['port'], map['driver']),
      database: map['database'] as String,
      username: map['username'] as String?,
      password: map['password'] as String?,
      isUnixSocket:
          _bool(key(['is_unix_socket', 'isUnixSocket']), 'is_unix_socket') ??
              false,
      charset: map['charset'] as String?,
      pool: _bool(map['pool'], 'pool') ?? false,
      poolSize:
          _int(key(['poolsize', 'pool_size', 'poolSize']), 'poolsize') ?? 1,
      applicationName: key(['application_name', 'applicationName']) as String?,
      allowReconnect: _bool(
          key(['allowreconnect', 'allow_reconnect', 'allowReconnect']),
          'allowreconnect'),
      sslmode: sslmode,
      timezone: map['timezone'] as String?,
      schema: map['schema'] as String?,
    );
    co.collation = map['collation'] as String?;
    if (map['forceDecodeTimestamptzAsUTC'] is bool) {
      co.forceDecodeTimestamptzAsUTC =
          map['forceDecodeTimestamptzAsUTC'] as bool;
    }
    if (map['forceDecodeTimestampAsUTC'] is bool) {
      co.forceDecodeTimestampAsUTC = map['forceDecodeTimestampAsUTC'] as bool;
    }
    if (map['forceDecodeDateAsUTC'] is bool) {
      co.forceDecodeDateAsUTC = map['forceDecodeDateAsUTC'] as bool;
    }
    co.dateTimeBindings = parseDateTimeBindings(map['datetime_bindings']);
    co.pgTypes = parsePgTypes(map['pg_types']);
    final driverOptions = key(['driver_options', 'driverOptions']);
    if (driverOptions != null) {
      if (driverOptions is! Map) {
        throw ArgumentError.value(
            driverOptions, 'driver_options', 'Expected a Map.');
      }
      co.driverOptions = Map<String, dynamic>.from(driverOptions);
    }
    // Both spellings are accepted; the snake_case keys were silently ignored.
    String? timeout(String camel, String snake) =>
        (map[camel] ?? map[snake])?.toString();
    co.statementTimeout =
        timeout('statementTimeout', 'statement_timeout') ?? co.statementTimeout;
    co.lockTimeout = timeout('lockTimeout', 'lock_timeout') ?? co.lockTimeout;
    co.idleInTransactionSessionTimeout = timeout(
            'idleInTransactionSessionTimeout',
            'idle_in_transaction_session_timeout') ??
        co.idleInTransactionSessionTimeout;

    return co;
  }

  /// The `port` config value: an int or a numeric string; null or `''` is
  /// the default port of [driver] (3306 for `mysql`, 5432 otherwise).
  static int _port(dynamic value, dynamic driver) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      return driver == 'mysql' ? 3306 : 5432;
    }
    return _int(value, 'port')!;
  }

  /// An int config value, also given as a numeric string (an environment
  /// variable).
  static int? _int(dynamic value, String name) {
    if (value == null || value is int) return value as int?;
    final parsed = int.tryParse(value.toString().trim());
    if (parsed == null) {
      throw ArgumentError.value(value, name, 'Expected an integer.');
    }
    return parsed;
  }

  /// A bool config value, also given as `'true'`/`'false'` or `1`/`0`.
  static bool? _bool(dynamic value, String name) {
    if (value == null || value is bool) return value as bool?;
    switch (value.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
    throw ArgumentError.value(value, name, 'Expected true or false.');
  }

  /// Parses the `sslmode` config value (`null` or `''` means `disable`).
  ///
  /// Accepts libpq's names (`disable`, `allow`, `prefer`, `require`,
  /// `verify-ca`, `verify-full`), in any case and with `-`, `_` or no
  /// separator, and MySQL's (`DISABLED`, `PREFERRED`, `REQUIRED`,
  /// `VERIFY_CA`, `VERIFY_IDENTITY`). Throws [ArgumentError] for any other
  /// value: a typo must not turn TLS off.
  static PDOSslMode parseSslMode(dynamic value) {
    if (value == null) return PDOSslMode.disable;
    if (value is PDOSslMode) return value;
    final name =
        value.toString().trim().toLowerCase().replaceAll(RegExp('[-_]'), '');
    switch (name) {
      case '':
      case 'disable':
      case 'disabled':
        return PDOSslMode.disable;
      case 'allow':
        return PDOSslMode.allow;
      case 'prefer':
      case 'preferred':
        return PDOSslMode.prefer;
      case 'require':
      case 'required':
        return PDOSslMode.require;
      case 'verifyca':
        return PDOSslMode.verifyCa;
      case 'verifyfull':
      case 'verifyidentity':
        return PDOSslMode.verifyFull;
    }
    throw ArgumentError.value(value, 'sslmode',
        'Expected disable, allow, prefer, require, verify-ca or verify-full');
  }

  /// [parsedSslMode] for a PostgreSQL driver that cannot fall back to a
  /// plain connection by itself: `allow` and `prefer` become `require` when
  /// the server accepts TLS (see [pgServerAcceptsSsl]) and `disable`
  /// otherwise. The other modes are returned as they are.
  Future<PDOSslMode> resolvePgSslMode({Duration? timeout}) async {
    final mode = parsedSslMode;
    if (mode != PDOSslMode.allow && mode != PDOSslMode.prefer) return mode;
    return await pgServerAcceptsSsl(host, port,
            timeout: timeout ?? const Duration(seconds: 15))
        ? PDOSslMode.require
        : PDOSslMode.disable;
  }

  /// Whether the PostgreSQL server at [host]:[port] accepts TLS: sends an
  /// SSLRequest, reads the one-byte answer (`S` or `N`) and closes the
  /// socket.
  static Future<bool> pgServerAcceptsSsl(String host, int port,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(const [0, 0, 0, 8, 4, 210, 22, 47]);
      await socket.flush();
      final answer = await socket.first.timeout(timeout);
      return answer.isNotEmpty && answer.first == 0x53;
    } finally {
      socket.destroy();
    }
  }

  /// [value] as a PostgreSQL string literal, as `quote_literal` writes it:
  /// single quotes doubled and, when there is a backslash, the `E''` form
  /// with backslashes doubled.
  static String quotePgLiteral(String value) {
    final quoted = value.replaceAll("'", "''");
    if (!quoted.contains(r'\')) return "'$quoted'";
    return "E'${quoted.replaceAll(r'\', r'\\')}'";
  }

  /// Normalizes a PostgreSQL timeout setting: "3000" (ms), "250ms", "3s",
  /// "2min" or "0" (disabled).
  static String normalizePgTimeout(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == '0' || s == '0ms' || s == '0s' || s == '0min') return '0';
    if (['ms', 's', 'min'].any((u) => s.endsWith(u))) return s;
    if (RegExp(r'^\d+$').hasMatch(s)) return '${s}ms';
    throw ArgumentError(
        'Timeout inválido: "$raw". Use "250ms", "3s", "2min" ou "0".');
  }

  /// A timeout setting ("3000", "250ms", "3s", "2min", "0") in milliseconds.
  static int timeoutToMilliseconds(String raw) {
    final s = normalizePgTimeout(raw);
    if (s == '0') return 0;
    if (s.endsWith('ms')) return int.parse(s.substring(0, s.length - 2));
    if (s.endsWith('min')) {
      return (double.parse(s.substring(0, s.length - 3)) * 60000).round();
    }
    return (double.parse(s.substring(0, s.length - 1)) * 1000).round();
  }

  /// `SET statement_timeout/lock_timeout/idle_in_transaction_session_timeout`
  /// statements for the configured PostgreSQL session timeouts.
  /// Parses the `pg_types` config value (`null` means `uniform`).
  static PgTypes parsePgTypes(dynamic value) {
    if (value == null) return PgTypes.uniform;
    if (value is PgTypes) return value;
    switch (value.toString().toLowerCase()) {
      case 'uniform':
        return PgTypes.uniform;
      case 'driver':
        return PgTypes.driver;
    }
    throw ArgumentError.value(
        value, 'pg_types', "Expected 'uniform' or 'driver'.");
  }

  /// [driverOptions] checked against the keys an adapter accepts: an
  /// unknown key (a typo) throws instead of being ignored.
  DriverOptions driverOptionsFor(String driver, Set<String> known) =>
      DriverOptions(driver, driverOptions, known);

  /// Parses the `datetime_bindings` config value (`null` means `string`).
  static DateTimeBindings parseDateTimeBindings(dynamic value) {
    if (value == null) return DateTimeBindings.string;
    if (value is DateTimeBindings) return value;
    switch (value.toString().toLowerCase()) {
      case 'string':
        return DateTimeBindings.string;
      case 'native':
        return DateTimeBindings.native;
    }
    throw ArgumentError.value(
        value, 'datetime_bindings', "Expected 'string' or 'native'.");
  }

  List<String> postgresTimeoutStatements() {
    final statements = <String>[];
    void add(String name, String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      statements.add('SET $name = ${quotePgLiteral(normalizePgTimeout(raw))}');
    }

    add('statement_timeout', statementTimeout);
    add('lock_timeout', lockTimeout);
    add('idle_in_transaction_session_timeout', idleInTransactionSessionTimeout);
    return statements;
  }
}

/// `driver_options` of one adapter, with typed accessors.
class DriverOptions {
  DriverOptions(this.driver, this.values, Set<String> known) {
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError.value(
          unknown.join(', '),
          'driver_options',
          'Unknown option for $driver. Known options: '
              '${(known.toList()..sort()).join(', ')}');
    }
  }

  final String driver;
  final Map<String, dynamic> values;

  bool has(String key) => values.containsKey(key);

  T? _typed<T>(String key, T? Function(Object value) convert) {
    final value = values[key];
    if (value == null) return null;
    final converted = convert(value as Object);
    if (converted == null) {
      throw ArgumentError.value(value, 'driver_options.$key',
          'Invalid value for $driver (expected $T)');
    }
    return converted;
  }

  bool? flag(String key) => _typed(key, (v) {
        if (v is bool) return v;
        if (v == 'true') return true;
        if (v == 'false') return false;
        return null;
      });

  int? integer(String key) =>
      _typed(key, (v) => v is int ? v : int.tryParse('$v'));

  String? text(String key) => _typed(key, (v) => '$v');

  /// One of [values], given as the value itself or by its name.
  T? enumeration<T extends Enum>(String key, List<T> values) =>
      _typed(key, (v) => v is T ? v : values.asNameMap()['$v']);

  /// A Duration, or a number of seconds.
  Duration? duration(String key) => _typed(key, (v) {
        if (v is Duration) return v;
        final seconds = v is num ? v : num.tryParse('$v');
        return seconds == null
            ? null
            : Duration(microseconds: (seconds * 1000000).round());
      });
}
