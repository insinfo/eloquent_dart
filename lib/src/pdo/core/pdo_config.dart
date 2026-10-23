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

    final co = PDOConfig(
      driver: map['driver'],
      host: map['host'],
      port: map['port'] is int ? map['port'] : int.parse(map['port']),
      database: map['database'],
      username: map['username'],
      password: map['password'],
      isUnixSocket: key(['is_unix_socket', 'isUnixSocket']),
      charset: map['charset'],
      pool: map['pool'],
      poolSize: key(['poolsize', 'pool_size', 'poolSize']),
      applicationName: key(['application_name', 'applicationName']),
      allowReconnect:
          key(['allowreconnect', 'allow_reconnect', 'allowReconnect']),
      sslmode: map['sslmode'],
      timezone: map['timezone'],
      schema: map['schema'],
    );
    if (map['forceDecodeTimestamptzAsUTC'] is bool) {
      co.forceDecodeTimestamptzAsUTC = map['forceDecodeTimestamptzAsUTC'];
    }
    if (map['forceDecodeTimestampAsUTC'] is bool) {
      co.forceDecodeTimestampAsUTC = map['forceDecodeTimestampAsUTC'];
    }
    if (map['forceDecodeDateAsUTC'] is bool) {
      co.forceDecodeDateAsUTC = map['forceDecodeDateAsUTC'];
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
      statements.add("SET $name = '${normalizePgTimeout(raw)}'");
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
    final converted = convert(value);
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
