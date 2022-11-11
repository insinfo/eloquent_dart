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
    'params': {}
  };

  DSNParser(this.dsn, [this.dsnType = DsnType.pdoPostgreSql]) {
    parse();
  }

  DSNParser parse() {
    //dado isso: pgsql:host=localhost;port=5432;dbname=dvdrental;
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

      dsnParts['host'] =
          parts.lastWhere((p) => p.startsWith('host')).split('=').last;
      dsnParts['port'] =
          parts.lastWhere((p) => p.startsWith('port')).split('=').last;
      dsnParts['database'] =
          parts.lastWhere((p) => p.startsWith('dbname')).split('=').last;
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

  String getDSN() {
    var dsn = (dsnParts['driver'] ?? '') +
        '://' +
        (dsnParts['user']
            ? ((dsnParts['user'] ?? '') +
                (dsnParts['password'] ? ':' + dsnParts['password'] : '') +
                '@')
            : '') +
        (dsnParts['host'] ?? '') +
        (dsnParts['port'] ? ':' + dsnParts['port'] : '') +
        '/' +
        (dsnParts['database'] ?? '');

    if (dsnParts['params'] && (dsnParts['params'] as Map).keys.length > 0) {
      dsn += '?' + toQueryParams(dsnParts['params']);
    }
    return dsn;
  }

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
        '"}');
  }

  String toQueryParams(Map<String, dynamic> obj) {
    var str = [];
    for (var entry in obj.entries) {
      str.add(Uri.encodeComponent(entry.key) +
          '=' +
          Uri.encodeComponent(entry.value));
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
