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
      //'sslmode': 'require',
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

    test('select', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS clients ( id int NOT NULL AUTO_INCREMENT, name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');
      await db.table('clients').insert({'name': 'John Doe'});      
      final res = await db.table('clients').where('id','=',1).first();
      expect(res, {'id': 1, 'name': 'John Doe'});
    });

    test('insert', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS clients ( id int NOT NULL AUTO_INCREMENT, name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');
      final res = await db.table('clients').insert({'name': 'John Doe'});
      expect(res, []);
    });

    test('insert and get id', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS clients ( id int NOT NULL AUTO_INCREMENT, name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');
      final res = await db.table('clients').insertGetId({'name': 'John Doe'});
      expect(res, 1);
    });

    test('update', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS clients ( id int NOT NULL AUTO_INCREMENT, name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');
      await db.table('clients').insert({'name': 'John Doe'});
      await db.table('clients').where('id','=',1).update({'name': 'John Doe 2'});
      final res = await db.table('clients').where('id','=',1).first();
      expect(res, {'id': 1, 'name': 'John Doe 2'});
    });
  });
}
