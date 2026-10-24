import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:test/test.dart';

void main() {
  group('DSNParser', () {
    test('getDSN of a PDO DSN without user and password', () {
      final d = DSNParser('pgsql:host=localhost;port=5432;dbname=dvdrental;');
      expect(d.getDSN(), 'pgsql://localhost:5432/dvdrental');
    });

    test('getDSN of a heroku URL keeps user, password, port and params', () {
      final d = DSNParser(
          'pgsql://user:pass@127.0.0.1:5432/my_db?pram=0', DsnType.heroku);
      expect(d.getDSN(), 'pgsql://user:pass@127.0.0.1:5432/my_db?pram=0');
    });

    test('port of a heroku URL (parsed as an int)', () {
      final d = DSNParser(
          'pgsql://user:pass@127.0.0.1:5432/my_db?pram=0', DsnType.heroku);
      expect(d.port, 5432);
      expect(d.user, 'user');
      expect(d.password, 'pass');
      expect(d.params, {'pram': '0'});
    });

    test('a PDO DSN has no user, password or params', () {
      final d = DSNParser('pgsql:host=localhost;port=5433;dbname=db;');
      expect(d.port, 5433);
      expect(d.user, isNull);
      expect(d.password, isNull);
      expect(d.params, isEmpty);
    });

    test('options is the value written in the DSN', () {
      final d = DSNParser('pgsql:host=localhost;dbname=db;options=-c');
      expect(d.options, '-c');
    });
  });
}
