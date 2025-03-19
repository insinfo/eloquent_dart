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
    });
    manager.setAsGlobal();
    db = await manager.connection();
  });

  group('QueryBuilder - Operações Básicas', () {
    test('exec command simple', () async {
      final res = await db.execute("SELECT 'TEST'");
      expect(res, [0]);
    });

    test('select', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'John Doe'});
      final res = await db.table('clients').where('id', '=', 1).first();
      expect(res, {'id': 1, 'name': 'John Doe'});
    });

    test('insert', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      final res = await db.table('clients').insert({'name': 'John Doe'});
      // Dependendo da implementação, insert pode retornar uma lista vazia.
      expect(res, []);
    });

    test('insert and get id', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      final res = await db.table('clients').insertGetId({'name': 'John Doe'});
      expect(res, 1);
    });

    test('update', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'John Doe'});
      await db.table('clients').where('id', '=', 1).update({'name': 'John Doe 2'});
      final res = await db.table('clients').where('id', '=', 1).first();
      expect(res, {'id': 1, 'name': 'John Doe 2'});
    });
  });

  group('QueryBuilder - Testes Adicionais', () {
    test('delete record', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'John Doe'});
      await db.table('clients').where('id', '=', 1).delete();
      final res = await db.table('clients').where('id', '=', 1).first();
      expect(res, isNull);
    });

    // test('truncate table', () async {
    //   await db.execute('DROP TABLE IF EXISTS clients');
    //   await db.execute('''
    //     CREATE TABLE IF NOT EXISTS clients (
    //       id int NOT NULL AUTO_INCREMENT,
    //       name varchar(255) NOT NULL,
    //       PRIMARY KEY (id)
    //     );
    //   ''');
    //   await db.table('clients').insert({'name': 'Alice'});
    //   await db.table('clients').insert({'name': 'Bob'});
    //   await db.table('clients').insert({'name': 'Charlie'});
    //   await db.table('clients').truncate();
    //   final res = await db.table('clients').get();
    //   expect(res, isEmpty);
    // });

    test('whereIn', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'Alice'});
      await db.table('clients').insert({'name': 'Bob'});
      await db.table('clients').insert({'name': 'Charlie'});
      // Consulta usando whereIn – assumindo que o método whereIn está implementado.
      final res = await db.table('clients').whereIn('name', ['Alice', 'Charlie']).get();
      expect(res.length, equals(2));
      final names = res.map((row) => row['name']).toList();
      expect(names, containsAll(['Alice', 'Charlie']));
    });

    test('increment and decrement', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          score int NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'John Doe', 'score': 10});
      await db.table('clients').where('id', '=', 1).increment('score', 5);
      var res = await db.table('clients').where('id', '=', 1).first();
      expect(res?['score'], equals(15));
      await db.table('clients').where('id', '=', 1).decrement('score', 3);
      res = await db.table('clients').where('id', '=', 1).first();
      expect(res?['score'], equals(12));
    });

    test('pluck', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'Alice'});
      await db.table('clients').insert({'name': 'Bob'});
      await db.table('clients').insert({'name': 'Charlie'});
      final res = await db.table('clients').pluck('name');
      expect(res, isA<List>());
      expect(res, containsAll(['Alice', 'Bob', 'Charlie']));
    });

    // test('updateOrInsert', () async {
    //   await db.execute('DROP TABLE IF EXISTS clients');
    //   await db.execute('''
    //     CREATE TABLE IF NOT EXISTS clients (
    //       id int NOT NULL AUTO_INCREMENT,
    //       name varchar(255) NOT NULL,
    //       email varchar(255),
    //       PRIMARY KEY (id)
    //     );
    //   ''');
    //   // Primeiro, insere o registro pois ele não existe.
    //   var result = await db.table('clients')
    //       .updateOrInsert({'email': 'john@example.com'}, {'name': 'John Doe'});
    //   expect(result, isTrue);
    //   var res = await db.table('clients').where('email', '=', 'john@example.com').first();
    //   expect(res, isNotNull);
    //   expect(res?['name'], equals('John Doe'));
    //   // Agora, atualiza o registro existente.
    //   result = await db.table('clients')
    //       .updateOrInsert({'email': 'john@example.com'}, {'name': 'John Doe Updated'});
    //   expect(result, isTrue);
    //   res = await db.table('clients').where('email', '=', 'john@example.com').first();
    //   expect(res, isNotNull);
    //   expect(res?['name'], equals('John Doe Updated'));
    // });

    test('chunk', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      await db.table('clients').insert({'name': 'Alice'});
      await db.table('clients').insert({'name': 'Bob'});
      await db.table('clients').insert({'name': 'Charlie'});
      await db.table('clients').insert({'name': 'David'});
      await db.table('clients').insert({'name': 'Eve'});
      
      var totalCount = 0;
      final chunkResult = await db.table('clients').chunk(2, (chunk, page) async {
        totalCount += chunk.length;
        return true;
      });
      expect(chunkResult, isTrue);
      expect(totalCount, equals(5));
    });

    test('paginate', () async {
      await db.execute('DROP TABLE IF EXISTS clients');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL,
          PRIMARY KEY (id)
        );
      ''');
      for (int i = 1; i <= 10; i++) {
        await db.table('clients').insert({'name': 'Client $i'});
      }
      final paginator = await db.table('clients').paginate(perPage: 5);
      expect(paginator.total(), equals(10));
      expect(paginator.perPage(), equals(5));
      expect(paginator.currentPage(), equals(1));
      expect(paginator.items().length, equals(5));
    });
  });
}
