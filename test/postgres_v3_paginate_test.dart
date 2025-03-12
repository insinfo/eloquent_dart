import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  late Connection db;

  setUp(() async {
    // Configuração do gerenciador e conexão com o banco de dados.
    var manager = Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'postgres_v3',
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'prefix': '',
      'schema': ['public'],
    });
    manager.setAsGlobal();
    db = await manager.connection();

    // Configura um schema e uma tabela para o teste de paginação.
    try {
      await db.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
    } catch (e) {
      // Ignora se não existir.
    }
    await db.execute('CREATE SCHEMA myschema;');
    await db.execute('SET search_path TO myschema;');

    // Cria uma tabela para o teste.
    await db.execute('''
      CREATE TABLE test_items (
        id serial PRIMARY KEY,
        name VARCHAR(80)
      );
    ''');

    // Insere 25 registros para teste.
    for (int i = 1; i <= 25; i++) {
      await db.table('test_items').insert({'name': 'Item $i'});
    }
  });

  tearDown(() async {
    // Remove o schema de teste
    await db.execute('DROP SCHEMA myschema CASCADE;');
  });

  group('Paginate tests', () {
    test('Paginate retorna informações corretas e os itens esperados', () async {
      // Seleciona os itens ordenados por id (ascendente)
      final query = db.table('test_items').select(['id', 'name']).orderBy('id', 'asc');

      // Chama paginate com 10 itens por página e solicita a página 2.
      final paginator = await query.paginate(perPage: 10, page: 2);

      // Verifica se o total de itens é 25
      expect(paginator.total(), equals(25));
      // A página atual deve ser 2
      expect(paginator.currentPage(), equals(2));
      // O número da última página deve ser 3 (25/10 arredondado para cima)
      expect(paginator.lastPage(), equals(3));

      // Verifica se os itens retornados correspondem à página 2:
      // Os registros esperados são os de id 11 até 20.
      final items = paginator.items();
      expect(items.length, equals(10));
      expect(items.first['id'], equals(11));
      expect(items.last['id'], equals(20));
    });

    test('Paginate retorna paginator vazio quando não há registros', () async {
      // Remove todos os registros da tabela.
      await db.execute('TRUNCATE TABLE test_items;');

      final query = db.table('test_items').select(['id', 'name']);
      final paginator = await query.paginate(perPage: 10, page: 1);

      expect(paginator.total(), equals(0));
      expect(paginator.items(), isEmpty);
    });
  });
}
