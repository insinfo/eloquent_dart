import 'dart:convert';

enum DsnType { pdoMySql, pdoPostgreSql, jdbc, heroku }

/// JDBC URL EXAMPLE: jdbc:sqlserver://localhost;encrypt=true;user=MyUserName;password=*****;
/// O pdoPostgreSql Data Source Name (DSN) é composto dos seguintes elementos:
///
/// DSN prefix
/// O prefixo DSN é pgsql:
/// host => O hostname no qual o servidor do banco de dados está.
/// port -> O número da porta onde o servidor do banco de dados está escutando.
/// dbname -> O nome do banco de dados.
/// unix_socket -> O socket Unix do MySQL (não deve ser usado com host ou port).
/// charset
///
/// Example:
/// ```dart
///  var d = DSNParser('pgsql:host=localhost;port=5432;dbname=dvdrental;', DsnType.pdoPostgreSql);
///  print(d.getDnsParts());
///  //Result: {driver: pgsql, user: null, password: null, host: localhost, port: 5432, database: dvdrental, params: {}}
///
///  var d = DSNParser('pgsql://user:pass@127.0.0.1:5432/my_db?pram=0', DsnType.heroku);
///  print(d.getDnsParts());
///  //Result: {driver: pgsql, user: null, password: null, host: localhost, port: 5432, database: dvdrental, params: {}}
/// ```
///
class DSNParser {
  String dsn;
  DsnType dsnType = DsnType.pdoPostgreSql;

  Map<String, dynamic> dsnParts = {
    'driver': null,
    'user': null,
    'password': null,
    'host': null,
    'port': null,
    'database': null,
    'charset': null,
    'params': <String, dynamic>{}
  };

  String? get password => dsnParts['password'] as String?;
  String? get user => dsnParts['user'] as String?;
  String? get host => dsnParts['host'] as String?;
  String? get driver => dsnParts['driver'] as String?;

  /// The port, 0 when there is none: a PDO DSN keeps it as written, a
  /// heroku URL as an int.
  int get port {
    final port = dsnParts['port'];
    if (port == null) return 0;
    return port is int ? port : int.parse(port as String);
  }

  String? get database => dsnParts['database'] as String?;
  String? get charset => dsnParts['charset'] as String?;

  bool get pool => dsnParts['pool'].toString() == 'true';
  int get poolSize => int.tryParse(dsnParts['poolsize'] as String? ?? '') ?? 1;
  bool get allowReconnect => dsnParts['allowreconnect'].toString() == 'true';
  String? get applicationName => dsnParts['application_name'] as String?;
  String? get sslmode => dsnParts['sslmode'] as String?;
  String? get timezone => dsnParts['timezone'] as String?;
  String? get schema => dsnParts['schema'] as String?;

  /// The `options` value as written in the DSN.
  String? get options => dsnParts['options'] as String?;
  Map<String, dynamic> get params => dsnParts['params'] as Map<String, dynamic>;

  DSNParser(this.dsn, [this.dsnType = DsnType.pdoPostgreSql]) {
    parse();
  }

  DSNParser parse() {
    //dado isso: pgsql:host=localhost;port=5432;dbname=dvdrental;
    //dsn: pgsql:host=localhost;dbname=siamweb;port=5433;charset=latin1;pool=true;poolsize=1;allowreconnect=true
    if (dsnType == DsnType.pdoPostgreSql) {
      if (dsn.contains(':')) {
        dsnParts['driver'] = dsn.split(':').first.trim();
      } else {
        throw Exception('Syntax error: DSN not contains "driver:..." ');
      }
      var parts = <String>[];
      parts = dsn.split(':');
      parts.removeAt(0);
      parts = parts.join().split(';');

      if (parts.last.trim() == '') {
        parts.removeLast();
      }

      //dsnParts['host'] = parts.lastWhere((p) => p == 'host').split('=').last;
      //dsnParts['port'] = parts.lastWhere((p) => p == 'port').split('=').last;
      //dsnParts['database'] = parts.lastWhere((p) => p == 'dbname').split('=').last;

      if (parts.join().contains('dbname=')) {
        dsnParts['database'] =
            parts.lastWhere((p) => p.contains('dbname=')).split('=').last;
      }

      if (parts.join().contains('port=')) {
        dsnParts['port'] =
            parts.lastWhere((p) => p.contains('port=')).split('=').last;
      }

      //print('dsn_parser $parts');
      if (parts.join().contains('host=')) {
        dsnParts['host'] =
            parts.lastWhere((p) => p.contains('host=')).split('=').last;
      }

      if (parts.join().contains('charset=')) {
        dsnParts['charset'] =
            parts.lastWhere((p) => p.contains('charset=')).split('=').last;
      }
      if (parts.join().contains('pool=')) {
        dsnParts['pool'] =
            parts.lastWhere((p) => p.contains('pool=')).split('=').last;
      }
      if (parts.join().contains('poolsize=')) {
        dsnParts['poolsize'] =
            parts.lastWhere((p) => p.contains('poolsize=')).split('=').last;
      }
      if (parts.join().contains('allowreconnect=')) {
        dsnParts['allowreconnect'] = parts
            .lastWhere((p) => p.contains('allowreconnect='))
            .split('=')
            .last;
      }
      if (parts.join().contains('application_name=')) {
        dsnParts['application_name'] = parts
            .lastWhere((p) => p.contains('application_name='))
            .split('=')
            .last;
      }
      if (parts.join().contains('sslmode=')) {
        dsnParts['sslmode'] =
            parts.lastWhere((p) => p.contains('sslmode=')).split('=').last;
      }
      if (parts.join().contains('options=')) {
        dsnParts['options'] =
            parts.lastWhere((p) => p.contains('options=')).split('=').last;
      }

      if (parts.join().contains('timezone=')) {
        dsnParts['timezone'] =
            parts.lastWhere((p) => p.contains('timezone=')).split('=').last;
      }

      if (parts.join().contains('schema=')) {
        dsnParts['schema'] =
            parts.lastWhere((p) => p.contains('schema=')).split('=').last;
      }
    } else if (dsnType == DsnType.heroku) {
      var patternString = '^' +
          '(?:' +
          '([^:/?#.]+)' + // driver
          ':)?' +
          r'(?://' +
          '(?:([^/?#]*)@)?' + // auth
          '([\\w\\d\\-\\u0100-\\uffff.%]*)' + // host
          '(?::([0-9]+))?' + // port
          ')?' +
          '([^?#]+)?' + // database
          r'(?:\?([^#]*))?' + // params
          r'$';

      var regexp = RegExp(patternString, multiLine: true, caseSensitive: true);

      var matche = regexp.firstMatch(dsn);

      if (matche != null) {
        var split = <String?>[];
        for (var i = 0; i < matche.groupCount + 1; i++) {
          split.add(matche[i]);
        }

        var auth = split[2] != null ? split[2]?.split(':') : [];

        this.dsnParts = {
          'driver': split[1],
          'user': auth?[0],
          'password': auth?[1],
          'host': split[3],
          'port': split[4] != null ? int.parse(split[4]!, radix: 10) : null,
          'database': stripLeadingSlash(split[5]),
          'params': split.length < 7 ? {} : fromQueryParams(split[6])
        };
      }
    }
    return this;
  }

  /// Returns the parts as a URL: `driver://user:password@host:port/database`
  /// followed by the query parameters; a part that is null or empty is left
  /// out with its separator.
  String getDSN() {
    final user = dsnParts['user'];
    final password = dsnParts['password'];
    final port = dsnParts['port'];
    final params = dsnParts['params'];
    var dsn = '${dsnParts['driver'] ?? ''}://' +
        (_isGiven(user)
            ? '$user' + (_isGiven(password) ? ':$password' : '') + '@'
            : '') +
        '${dsnParts['host'] ?? ''}' +
        (_isGiven(port) ? ':$port' : '') +
        '/' +
        '${dsnParts['database'] ?? ''}';

    if (params is Map && params.isNotEmpty) {
      dsn += '?' + toQueryParams(Map<String, dynamic>.from(params));
    }
    return dsn;
  }

  /// Whether the DSN part [value] is given: not null and not empty.
  static bool _isGiven(dynamic value) => value != null && '$value' != '';

  Map<String, dynamic> getDnsParts() {
    return dsnParts;
  }

  Map<String, dynamic> fromQueryParams(String? params) {
    if (params == null) {
      return {};
    }

    return jsonDecode('{"' +
        Uri.decodeComponent(params)
            .replaceAll('"', '\\"')
            .replaceAll('&', '","')
            .replaceAll('=', '":"') +
        '"}') as Map<String, dynamic>;
  }

  String toQueryParams(Map<String, dynamic> obj) {
    var str = [];
    for (var entry in obj.entries) {
      str.add(Uri.encodeComponent(entry.key) +
          '=' +
          Uri.encodeComponent(entry.value as String));
    }
    return str.join('&');
  }

  String stripLeadingSlash(String? strP) {
    var str = strP ?? '';
    if (str.substring(0, 1) == '/') {
      return str.substring(1, str.length);
    }
    return str;
  }
}
