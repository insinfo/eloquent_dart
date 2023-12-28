import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  late Connection db;
  setUp(() async {
    var manager = Manager();
    manager.addConnection({
      'driver': 'mysql',
      'host': 'localhost',
      'port': '3306',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      // 'pool': true,
      // 'poolsize': 2,
    });
    manager.setAsGlobal();
    db = await manager.connection();
  });

  group('query', () {
    test('exec command simple', () async {
      final res = await db.execute(''' SELECT 'TEST'  ''');
      expect(res, [0]);
    });
    
  });
}
