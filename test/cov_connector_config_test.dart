// Connector and PDOConfig configuration handling, without a database:
// PDOConfig.fromMap defaults, sslmode validation, the search_path formatting
// of PostgresConnector, driver_implementation, the MySQL session statements
// and the read/write configuration of ConnectionFactory.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/connectors/mysql_connector.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/pdo/mysql_client/mysql_client_pdo.dart';
import 'package:eloquent/src/pdo/postgres/dependencies/postgres_pool/postgres_pool.dart';
import 'package:postgres_fork/postgres.dart' show PgSslMode;
import 'package:test/test.dart';

Map<String, dynamic> _pg([Map<String, dynamic> extra = const {}]) => {
      'driver': 'pgsql',
      'host': 'localhost',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      ...extra,
    };

void main() {
  group('PDOConfig.fromMap', () {
    test('without port uses the default port of the driver', () {
      expect(PDOConfig.fromMap(_pg()).port, 5432);
      expect(PDOConfig.fromMap({..._pg(), 'driver': 'mysql'}).port, 3306);
    });

    test('port as int or numeric string', () {
      expect(PDOConfig.fromMap(_pg({'port': 5433})).port, 5433);
      expect(PDOConfig.fromMap(_pg({'port': '5434'})).port, 5434);
      expect(PDOConfig.fromMap(_pg({'port': ''})).port, 5432);
    });

    test('an invalid port throws ArgumentError', () {
      expect(() => PDOConfig.fromMap(_pg({'port': 'abc'})),
          throwsA(isA<ArgumentError>()));
    });

    test('missing keys keep the constructor defaults', () {
      final config = PDOConfig.fromMap(_pg({'port': 5432}));
      expect(config.pool, isFalse);
      expect(config.poolSize, 1);
      expect(config.isUnixSocket, isFalse);
      // No charset default: the MySQL adapter falls back to its own
      // collation when charset is null.
      expect(config.charset, isNull);
    });

    test('pool, poolsize and allowreconnect given as strings', () {
      final config = PDOConfig.fromMap(_pg({
        'port': 5432,
        'pool': 'true',
        'poolsize': '4',
        'allowreconnect': 'false',
      }));
      expect(config.pool, isTrue);
      expect(config.poolSize, 4);
      expect(config.allowReconnect, isFalse);
    });

    test('an unknown sslmode throws ArgumentError naming the accepted values',
        () {
      expect(
          () => PDOConfig.fromMap(_pg({'sslmode': 'requir'})),
          throwsA(isA<ArgumentError>().having((e) => e.toString(), 'message',
              allOf(contains('verify-full'), contains('disable')))));
    });

    test('sslmode spellings', () {
      expect(PDOConfig.parseSslMode(null), PDOSslMode.disable);
      expect(PDOConfig.parseSslMode(''), PDOSslMode.disable);
      expect(PDOConfig.parseSslMode('REQUIRE'), PDOSslMode.require);
      expect(PDOConfig.parseSslMode(' prefer '), PDOSslMode.prefer);
      expect(PDOConfig.parseSslMode('allow'), PDOSslMode.allow);
      expect(PDOConfig.parseSslMode('verify-ca'), PDOSslMode.verifyCa);
      expect(PDOConfig.parseSslMode('verify_full'), PDOSslMode.verifyFull);
      expect(PDOConfig.parseSslMode('verifyFull'), PDOSslMode.verifyFull);
      // MySQL names.
      expect(PDOConfig.parseSslMode('REQUIRED'), PDOSslMode.require);
      expect(PDOConfig.parseSslMode('DISABLED'), PDOSslMode.disable);
      expect(PDOConfig.parseSslMode('PREFERRED'), PDOSslMode.prefer);
      expect(PDOConfig.parseSslMode('VERIFY_IDENTITY'), PDOSslMode.verifyFull);
    });

    test('toMap() reads back with fromMap()', () {
      final config = PDOConfig.fromMap(_pg({
        'port': '5433',
        'pool': true,
        'poolsize': 3,
        'application_name': 'app',
        'allowreconnect': true,
        'sslmode': 'require',
        'collation': 'utf8mb4_unicode_ci',
        'charset': 'utf8',
        'timezone': 'UTC',
        'schema': '"public"',
      }));
      expect(PDOConfig.fromMap(config.toMap()).toMap(), config.toMap());
      expect(config.collation, 'utf8mb4_unicode_ci');
    });

    test('quotePgLiteral doubles quotes and escapes backslashes', () {
      expect(PDOConfig.quotePgLiteral("app d'oeste"), "'app d''oeste'");
      expect(PDOConfig.quotePgLiteral(r'a\b'), r"E'a\\b'");
    });
  });

  group('PostgresConnector.formatSchema', () {
    final connector = PostgresConnector();

    test('doubles a double quote inside a name', () {
      expect(connector.formatSchema('my"schema'), '"my""schema"');
      expect(connector.formatSchema(['public', 'x"y']), '"public","x""y"');
    });

    test('a comma inside a quoted name does not split it', () {
      expect(connector.formatSchema('"a,b", c'), '"a,b","c"');
      // A quote inside an unquoted name does not open a quoted name.
      expect(connector.formatSchema(r'my"s, "a,b"'), '"my""s","a,b"');
      expect(connector.formatSchema('"x""y,z", w'), '"x""y,z","w"');
    });

    test('a lone double quote is a name, not a quoted one', () {
      expect(connector.formatSchema('"'), '""""');
      expect(connector.formatSchema('"abc'), '"""abc"');
    });

    test('names already quoted are kept', () {
      expect(connector.formatSchema('"my""schema", public'),
          '"my""schema","public"');
      expect(connector.formatSchema(r'"$user", public'), r'"$user","public"');
    });

    test('trims, skips empty names and drops duplicates', () {
      expect(connector.formatSchema(' public , ,other,public'),
          '"public","other"');
      expect(connector.formatSchema(['public', ' public ', '']), '"public"');
    });

    test('null, empty list and empty string give an empty result', () {
      expect(connector.formatSchema(null), '');
      expect(connector.formatSchema([]), '');
      expect(connector.formatSchema(''), '');
      expect(connector.formatSchema(' , '), '');
    });

    test('other types throw ArgumentError', () {
      expect(() => connector.formatSchema(42), throwsA(isA<ArgumentError>()));
    });
  });

  group('PostgresConnector driver_implementation', () {
    // Port 1 refuses the connection at once: a config that is accepted fails
    // with a socket error, not ArgumentError.
    final closed = {'host': '127.0.0.1', 'port': 1};

    test('an unknown value throws ArgumentError listing the drivers', () async {
      await expectLater(
          PostgresConnector()
              .connect(_pg({...closed, 'driver_implementation': 'postgress'})),
          throwsA(isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('postgres_v3'), contains('dargres'),
                  contains('dpgsql')))));
    });

    test('a known value, in any case, is not rejected', () async {
      // In parallel: a refused connection takes 2 s on Windows.
      await Future.wait([
        for (final name in [
          'postgres',
          'POSTGRES_V3',
          'dargres',
          'dpgsql',
          null,
        ])
          expectLater(
              PostgresConnector().connect(_pg({
                ...closed,
                if (name != null) 'driver_implementation': name,
              })),
              throwsA(isNot(isA<ArgumentError>())),
              reason: name),
      ]);
    });
  });

  group('postgres pool TLS mode', () {
    // PgPool used to know only "require" or plain, so verify-ca/verify-full
    // threw with pool: true; its endpoint now carries the TLS mode.
    test('PgEndpoint carries and parses the mode', () {
      final endpoint =
          PgEndpoint(host: 'h', database: 'd', sslMode: PgSslMode.verifyFull);
      expect(endpoint.toString(), contains('sslmode=verify-full'));
      expect(endpoint.replace(host: 'x').sslMode, PgSslMode.verifyFull);
      expect(endpoint == endpoint.replace(sslMode: PgSslMode.require), isFalse);
      for (final (text, mode) in [
        ('disable', PgSslMode.disable),
        ('prefer', PgSslMode.prefer),
        ('require', PgSslMode.require),
        ('verify-ca', PgSslMode.verifyFull),
        ('verify-full', PgSslMode.verifyFull),
      ]) {
        expect(PgEndpoint.parse('postgres://h:1/d?sslmode=$text').sslMode, mode,
            reason: text);
      }
    });
  });

  group('MySqlClientPDO.handshakeCollation', () {
    PDOConfig config(Map<String, dynamic> extra) => PDOConfig.fromMap(
        {'driver': 'mysql', 'host': 'h', 'database': 'd'}..addAll(extra));

    test('a charset name is not sent as the collation', () {
      expect(
          MySqlClientPDO.handshakeCollation(config({})), 'utf8mb4_general_ci');
      expect(MySqlClientPDO.handshakeCollation(config({'charset': 'utf8mb4'})),
          'utf8mb4_general_ci');
    });

    test('the collation key, or a collation given as charset', () {
      expect(
          MySqlClientPDO.handshakeCollation(config(
              {'charset': 'utf8mb4', 'collation': 'utf8mb4_unicode_ci'})),
          'utf8mb4_unicode_ci');
      expect(
          MySqlClientPDO.handshakeCollation(config({'charset': 'utf8mb4_bin'})),
          'utf8mb4_bin');
    });
  });

  group('MySqlConnector.sessionStatements', () {
    final connector = MySqlConnector();

    test('strict: false does not turn strict mode on', () {
      expect(connector.sessionStatements({'strict': false}),
          ["set session sql_mode='NO_ENGINE_SUBSTITUTION'"]);
    });

    test('strict: true has no mode removed in MySQL 8', () {
      final statements = connector.sessionStatements({'strict': true});
      expect(statements, hasLength(1));
      expect(statements.single, contains('STRICT_TRANS_TABLES'));
      expect(statements.single, isNot(contains('NO_AUTO_CREATE_USER')));
    });

    test('a null collation is not sent', () {
      expect(
          connector.sessionStatements({'charset': 'utf8', 'collation': null}),
          ["set names 'utf8'"]);
      expect(
          connector.sessionStatements(
              {'charset': 'utf8mb4', 'collation': 'utf8mb4_unicode_ci'}),
          ["set names 'utf8mb4' collate 'utf8mb4_unicode_ci'"]);
      // A collation given as charset.
      expect(connector.sessionStatements({'charset': 'utf8mb4_general_ci'}),
          ["set names 'utf8mb4' collate 'utf8mb4_general_ci'"]);
    });

    test('the time zone is a quoted string literal', () {
      expect(connector.sessionStatements({'timezone': "+00:00"}),
          ["set time_zone='+00:00'"]);
    });
  });

  group('ConnectionFactory read/write config', () {
    final factory = ConnectionFactory(Container());
    Map<String, dynamic> base() => {
          'driver': 'pgsql',
          'host': 'base-host',
          'database': 'db',
          'prefix': '',
        };

    test('read without write: the write config is the base config', () {
      final config = {
        ...base(),
        'read': {'host': 'read-host'},
      };
      final write = factory.getWriteConfig(config);
      expect(write['host'], 'base-host');
      expect(write.containsKey('read'), isFalse);
      expect(write.containsKey('write'), isFalse);
      expect(factory.getReadConfig(config)['host'], 'read-host');
    });

    test('write without read: the read config is the base config', () {
      final config = {
        ...base(),
        'write': {'host': 'write-host'},
      };
      final read = factory.getReadConfig(config);
      expect(read['host'], 'base-host');
      expect(read.containsKey('read'), isFalse);
      expect(read.containsKey('write'), isFalse);
      expect(factory.getWriteConfig(config)['host'], 'write-host');
    });

    test('the merged configs have no read/write keys', () {
      final config = {
        ...base(),
        'read': {'host': 'read-host'},
        'write': {'host': 'write-host'},
      };
      for (final merged in [
        factory.getReadConfig(config),
        factory.getWriteConfig(config)
      ]) {
        expect(merged.containsKey('read'), isFalse);
        expect(merged.containsKey('write'), isFalse);
      }
    });

    test("a read host list does not change the caller's map", () {
      final config = {
        ...base(),
        'read': {
          'host': ['r1', 'r2']
        },
      };
      final read = factory.getReadConfig(config);
      expect(['r1', 'r2'], contains(read['host']));
      expect((config['read'] as Map)['host'], ['r1', 'r2']);
    });

    test("parseConfig does not change the caller's map", () {
      final config = {'driver': 'pgsql', 'database': 'db'};
      final parsed = factory.parseConfig(config, 'a');
      expect(parsed['name'], 'a');
      expect(parsed['prefix'], '');
      expect(config.containsKey('name'), isFalse);
      // The same map registered under two names keeps each name.
      expect(factory.parseConfig(config, 'b')['name'], 'b');
    });

    test('a null prefix or name gets the default', () {
      final parsed = factory
          .parseConfig({'driver': 'pgsql', 'prefix': null, 'name': null}, 'a');
      expect(parsed['prefix'], '');
      expect(parsed['name'], 'a');
    });
  });
}
