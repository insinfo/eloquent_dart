import 'package:eloquent/eloquent.dart';

import 'package:test/test.dart';

/// test PostgresPDO
/// config['driver_implementation'] == 'postgres'
/// run: dart test .\test\postgres_query_test.dart -j 1 --chain-stack-traces --name 'update simple'
void main() {
  late Connection db;
  setUp(() async {
    var manager = new Manager();
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
      //'sslmode' => 'prefer',
    });
    manager.setAsGlobal();
    db = await manager.connection();
    //await db.execute('set password_encryption to scram-sha-256;');
    //await db.execute("set password_encryption to scram-sha-256; CREATE ROLE dart WITH LOGIN SUPERUSER PASSWORD 's1sadm1n';");
    //await db.execute('set password_encryption to scram-sha-256;');
    //await db.execute("set password_encryption to md5; CREATE ROLE usermd5 WITH LOGIN SUPERUSER PASSWORD 's1sadm1n';");
    //IF EXISTS
    try {
      await db.execute('DROP SCHEMA  myschema CASCADE;');
    } catch (e) {}
    // IF NOT EXISTS
    await db.execute('CREATE SCHEMA myschema;');
    await db.execute('SET search_path TO myschema;');
    await db.execute('''CREATE TABLE "temp_location" ( 
          id int4,
          city VARCHAR(80),
          street VARCHAR(80),
          id_people int4
        );''');
    await db.execute('''CREATE TABLE "people" ( 
          id int4,
          name VARCHAR(80),
          profession VARCHAR(80)
        );''');

    await db
        .table('people')
        .insert({'id': 1, 'name': 'Isaque', 'profession': 'Personal Trainer'});

    await db.execute(
        '''insert into "temp_location" ("id", "city", "street","id_people") values (1, 'Niteroi', 'Rua B',1)''');
  });
  group('query', () {
    test('exec command simple', () async {
      final res = await db.execute(''' SELECT 'TEST'  ''');
      expect(res, [1]);
    });

    test('insert simple', () async {
      var query = db.table('temp_location');
      var res = await query
          .insert({'id': 1, 'city': 'Rio de Janeiro', 'street': 'Rua R'});
      expect(res, []);
    });

    test('insertGetId simple', () async {
      final query = db.table('temp_location');
      final res = await query
          .insertGetId({'id': 1, 'city': 'Rio de Janeiro', 'street': 'Rua R'});
      expect(res, 1);
    });

    test('insertGetId simple with transaction', () async {
      final res = await db.transaction((ctx) async {
        final query = ctx.table('temp_location');
        final res = await query.insertGetId(
            {'id': 2, 'city': 'Rio de Janeiro', 'street': 'Rua R'});
        return res;
      });
      expect(res, 2);
    });

    test('select first', () async {
      final query = db.table('temp_location');
      final res = await query.select(['id', 'city', 'street']).first();
      expect(res, {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'});
    });

    test('select first with transaction', () async {
      final res = await db.transaction((ctx) async {
        final query = ctx.table('temp_location');
        final res = await query.select(['id', 'city', 'street']).first();
        return res;
      });
      expect(res, {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'});
    });

    test('select limit 1 get', () async {
      final query = db.table('temp_location');
      final res = await query.select(['id', 'city', 'street']).limit(1).get();
      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);
    });

    test('select limit 1 offset 0 get', () async {
      var query = db.table('temp_location');
      var res =
          await query.select(['id', 'city', 'street']).limit(1).offset(0).get();
      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);
    });

    test('select where limit 1 offset 0 get', () async {
      var query = db.table('temp_location');
      var res =
          await query.select().where('id', '=', 1).limit(1).offset(0).get();
      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B', 'id_people': 1}
      ]);
    });

    test('select inner join simple', () async {
      final query = db.table('temp_location');
      final res = await query
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
          .limit(1)
          .offset(0)
          .get();

      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);
    });

    ///dart test .\test\postgres_query_test.dart --name 'select inner join with callback' -j 1
    test('select inner join with callback', () async {
      final query = db.table('temp_location');
      final res = await query
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', (JoinClause q) {
            q.on('people.id', '=', 'temp_location.id_people');
          })
          .limit(1)
          .offset(0)
          .get();

      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);
    });

    ///dart test .\test\postgres_query_test.dart --name 'select inner join with callback and transaction' -j 1
    test('select inner join with callback and transaction', () async {
      final res = await db.transaction((ctx) async {
        final query = ctx.table('temp_location');
        final res = await query
            .select(['temp_location.id', 'city', 'street'])
            .where('temp_location.id', '=', 1)
            .join('people', (JoinClause q) {
              q.on('people.id', '=', 'temp_location.id_people');
            })
            .limit(1)
            .offset(0)
            .get();
        return res;
      });
      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);
    });

    test('update simple', () async {
      await db
          .table('temp_location')
          .where('id', '=', 1)
          .update({'city': 'Teresopolis'});

      final res = await db
          .table('temp_location')
          .select(['city'])
          .where('temp_location.id', '=', 1)
          .first();

      expect(res, {'city': 'Teresopolis'});
    });

    test('update simple with transaction', () async {
      final res = await db.transaction((ctx) async {
        await ctx
            .table('temp_location')
            .where('id', '=', 1)
            .update({'city': 'Teresopolis2'});

        final res = await ctx
            .table('temp_location')
            .select(['city'])
            .where('temp_location.id', '=', 1)
            .first();

        return res;
      });
      expect(res, {'city': 'Teresopolis2'});
    });

    test('delete simple', () async {
      var query = db.table('temp_location');
      var res = await query.where('id', '=', 1).delete();
      expect(res, 1);
    });

    test('select whereNotNull and orWhereNotNull', () async {
      // Preparar dados com valores nulos em 'temp_location'
      await db
          .table('temp_location')
          .insert({'id': 2, 'city': null, 'street': 'Rua X', 'id_people': 1});
      await db.table('temp_location').insert(
          {'id': 3, 'city': 'Petropolis', 'street': null, 'id_people': 1});

      var res = await db
          .table('temp_location')
          .select()
          .whereNotNull('city')
          .orWhereNotNull('street')
          .get();

      expect(
          res.length,
          greaterThanOrEqualTo(
              2)); // Ajuste a expectativa conforme os dados inseridos
      expect(res.any((row) => row['city'] != null || row['street'] != null),
          isTrue);
    });

    test('select whereDate, whereDay, whereMonth, whereYear', () async {
      // Assumindo que você tenha uma coluna 'created_at' do tipo data/timestamp em 'temp_location'
      await db.execute(
          '''ALTER TABLE "temp_location" ADD COLUMN created_at DATE;''');
      await db.execute(
          '''UPDATE "temp_location" SET created_at = '2024-07-20' WHERE id = 1;''');

      var resDate = await db
          .table('temp_location')
          .select()
          .whereDate('created_at', '=', DateTime(2024, 07, 20))
          .get();
      //print('resDate $resDate');

      expect(resDate.length, greaterThanOrEqualTo(1));

      var resDay = await db
          .table('temp_location')
          .select()
          .whereDay('created_at', '=', 20)
          .get();
      expect(resDay.length, greaterThanOrEqualTo(1));

      var resMonth = await db
          .table('temp_location')
          .select()
          .whereMonth('created_at', '=', 07)
          .get();
      expect(resMonth.length, greaterThanOrEqualTo(1));

      var resYear = await db
          .table('temp_location')
          .select()
          .whereYear('created_at', '=', 2024)
          .get();
      expect(resYear.length, greaterThanOrEqualTo(1));
    });

    test('select whereColumn', () async {
      // Preparar dados onde city e street são iguais para alguns registros
      await db.table('temp_location').insert(
          {'id': 2, 'city': 'Iguaba', 'street': 'Iguaba', 'id_people': 1});

      var res = await db
          .table('temp_location')
          .select()
          .whereColumn('city', '=', 'street')
          .get();
      expect(res.length, greaterThanOrEqualTo(1));
      expect(res.any((row) => row['city'] == row['street']), isTrue);
    });

    test('select whereRaw and orWhereRaw', () async {
      var res = await db
          .table('temp_location')
          .select()
          .whereRaw("city LIKE 'N%'")
          .get();
      expect(res.length, greaterThanOrEqualTo(1));
      expect(res.any((row) => (row['city'] as String).startsWith('N')), isTrue);

      var resOrRaw = await db
          .table('temp_location')
          .select()
          .where('id', '=', 2)
          .orWhereRaw("city LIKE 'N%'")
          .get();
      expect(
          resOrRaw.length, greaterThanOrEqualTo(1)); // Ajuste conforme os dados
    });

    test('select groupBy multiple columns', () async {
      // Preparar dados com diferentes cidades e ruas
      await db.table('temp_location').insert(
          {'id': 2, 'city': 'Niteroi', 'street': 'Rua C', 'id_people': 1});
      await db.table('temp_location').insert({
        'id': 3,
        'city': 'Rio de Janeiro',
        'street': 'Rua R',
        'id_people': 1
      });

      var res = await db
          .table('temp_location')
          .select(['city', 'street', db.raw('count(*) as total')]).groupBy(
              ['city', 'street']).get();

      expect(res.length, greaterThanOrEqualTo(2)); // Ajuste conforme os dados
    });

    test('select having and havingRaw', () async {
      // Garantir que haja duas linhas com a mesma city para count(*) > 1
      await db.table('temp_location').insert({
        'id': 2,
        'city': 'Niteroi',
        'street': 'Rua C',
        'id_people': 1,
      });
      // Cria uma subquery que agrupa por "city" e calcula o total
      var subQuery = db
          .table('temp_location')
          .selectRaw('city, count(*) as total')
          .groupBy('city');

      // Usa a subquery como fonte (tabela derivada) para que o alias "total" seja reconhecido.
      // Como a query externa utilizará HAVING, é necessário também agrupar (GROUP BY) na query externa.
      var resHaving = await db
          .query()
          .fromRaw('(' + subQuery.toSql() + ') as sub')
          .select(['city', 'total'])
          .groupBy(['city', 'total'])
          .having('total', '>', 1)
          .get();

      var resHavingRaw = await db
          .query()
          .fromRaw('(' + subQuery.toSql() + ') as sub')
          .select(['city', 'total']).groupBy(['city', 'total']).havingRaw(
              'total > ?', [1]).get();

      expect(resHaving, isNotEmpty);
      expect(resHavingRaw, isNotEmpty);
    });

    test('select orderBy multiple columns and directions', () async {
      // Cria uma tabela temporária para o teste
      await db.execute('''
    CREATE TEMP TABLE temp_location_test (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int
    );
  ''');

      // Insere os dados na tabela temporária
      final ids = [10, 11, 12, 13];
      await db.table('temp_location_test').insertGetId({
        'id': 10,
        'city': 'Niteroi',
        'street': 'Rua Y',
        'id_people': 1,
      });
      await db.table('temp_location_test').insertGetId({
        'id': 11,
        'city': 'Niteroi',
        'street': 'Rua X',
        'id_people': 1,
      });
      await db.table('temp_location_test').insertGetId({
        'id': 12,
        'city': 'Petropolis',
        'street': 'Rua Z',
        'id_people': 1,
      });
      await db.table('temp_location_test').insertGetId({
        'id': 13,
        'city': 'Petropolis',
        'street': 'Rua A',
        'id_people': 1,
      });

      // Realiza a consulta com ordenação:
      // 1) city em ordem ascendente e
      // 2) street em ordem descendente
      var resAscDesc = await db
          .table('temp_location_test')
          .select(['city', 'street'])
          .whereIn('id', ids)
          .orderBy('city', 'asc')
          .orderBy('street', 'desc')
          .get();

      expect(resAscDesc, isNotEmpty);

      expect(resAscDesc, [
        {'city': 'Niteroi', 'street': 'Rua Y'},
        {'city': 'Niteroi', 'street': 'Rua X'},
        {'city': 'Petropolis', 'street': 'Rua Z'},
        {'city': 'Petropolis', 'street': 'Rua A'},
      ]);
    });

    test('select orderByRaw', () async {
      // Cria uma tabela temporária para isolar os dados deste teste.
      await db.execute('''
    CREATE TEMP TABLE temp_location_raw (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int
    );
  ''');

      // Insere alguns registros para testar a ordenação.
      // A ordenação será baseada em LENGTH(city) em ordem DESC e street em ordem ASC.
      await db.table('temp_location_raw').insert({
        'id': 1,
        'city': 'Rio de Janeiro', // LENGTH = 15
        'street': 'Gamma',
        'id_people': 1,
      });
      await db.table('temp_location_raw').insert({
        'id': 2,
        'city': 'Petropolis', // LENGTH = 10
        'street': 'Epsilon',
        'id_people': 1,
      });
      await db.table('temp_location_raw').insert({
        'id': 3,
        'city': 'Sao Paulo', // LENGTH = 9 (contando espaço)
        'street': 'Beta',
        'id_people': 1,
      });
      await db.table('temp_location_raw').insert({
        'id': 4,
        'city': 'Niteroi', // LENGTH = 7
        'street': 'Delta',
        'id_people': 1,
      });
      await db.table('temp_location_raw').insert({
        'id': 5,
        'city': 'Rio', // LENGTH = 3
        'street': 'Alpha',
        'id_people': 1,
      });

      // Realiza a consulta utilizando orderByRaw:
      // - Ordena por LENGTH(city) em ordem DESC
      // - Em seguida, por street em ordem ASC
      var resRaw = await db
          .table('temp_location_raw')
          .select(['city', 'street'])
          .orderByRaw('LENGTH(city) DESC, street ASC')
          .get();

      // Verifica se o resultado possui a ordenação esperada:
      // 1. "Rio de Janeiro" (15) – Gamma
      // 2. "Petropolis" (10) – Epsilon
      // 3. "Sao Paulo" (9) – Beta
      // 4. "Niteroi" (7) – Delta
      // 5. "Rio" (3) – Alpha
      expect(resRaw, [
        {'city': 'Rio de Janeiro', 'street': 'Gamma'},
        {'city': 'Petropolis', 'street': 'Epsilon'},
        {'city': 'Sao Paulo', 'street': 'Beta'},
        {'city': 'Niteroi', 'street': 'Delta'},
        {'city': 'Rio', 'street': 'Alpha'},
      ]);
    });

    test('select limit and offset combinations', () async {
      // Cria uma tabela temporária para o teste
      await db.execute('''
    CREATE TEMP TABLE temp_location_limit (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int
    );
  ''');

      // Insere registros conhecidos na tabela temporária
      await db.table('temp_location_limit').insert({
        'id': 1,
        'city': 'City1',
        'street': 'Street1',
        'id_people': 1,
      });
      await db.table('temp_location_limit').insert({
        'id': 2,
        'city': 'City2',
        'street': 'Street2',
        'id_people': 1,
      });
      await db.table('temp_location_limit').insert({
        'id': 3,
        'city': 'City3',
        'street': 'Street3',
        'id_people': 1,
      });
      await db.table('temp_location_limit').insert({
        'id': 4,
        'city': 'City4',
        'street': 'Street4',
        'id_people': 1,
      });

      // Realiza a consulta com ORDER BY para garantir a ordem dos registros,
      // LIMIT para retornar 2 registros e OFFSET para pular o primeiro.
      var resLimitOffset = await db
          .table('temp_location_limit')
          .select(['id', 'city', 'street'])
          .orderBy('id', 'asc')
          .limit(2)
          .offset(1)
          .get();

      // Espera que exatamente 2 registros sejam retornados
      expect(resLimitOffset.length, equals(2));

      // Verifica se os registros retornados são os de id=2 e id=3
      expect(resLimitOffset, [
        {'id': 2, 'city': 'City2', 'street': 'Street2'},
        {'id': 3, 'city': 'City3', 'street': 'Street3'},
      ]);
    });

    test('select aggregate functions min, max, avg, sum with null cases',
        () async {
      // Cria uma tabela temporária para isolar os dados deste teste.
      await db.execute('''
    CREATE TEMP TABLE temp_location_temp (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int
    );
  ''');

      // ---- Cenário 1: Registros com valores não nulos ----
      await db.table('temp_location_temp').insert({
        'id': 1,
        'city': 'City1',
        'street': 'Street1',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': 2,
        'city': 'City2',
        'street': 'Street2',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': 3,
        'city': 'City3',
        'street': 'Street3',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': 4,
        'city': 'City4',
        'street': 'Street4',
        'id_people': 1,
      });

      var minId = await db.table('temp_location_temp').min('id');
      expect(minId, equals(1));

      var maxId = await db.table('temp_location_temp').max('id');
      expect(maxId, equals(4));

      var avgId = await db.table('temp_location_temp').avg('id');
      // Caso o valor venha como String, converte para double.
      var avgNumeric = avgId;
      expect(avgNumeric, closeTo(2.5, 0.01));

      var sumId = await db.table('temp_location_temp').sum('id');
      expect(sumId, equals(10));

      // ---- Cenário 2: Registros com todos os valores null ----
      await db.table('temp_location_temp').truncate();

      await db.table('temp_location_temp').insert({
        'id': null,
        'city': 'CityNull1',
        'street': 'StreetNull1',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': null,
        'city': 'CityNull2',
        'street': 'StreetNull2',
        'id_people': 1,
      });

      var minNull = await db.table('temp_location_temp').min('id');
      expect(minNull, isNull);

      var maxNull = await db.table('temp_location_temp').max('id');
      expect(maxNull, isNull);

      var avgNull = await db.table('temp_location_temp').avg('id');
      expect(avgNull, isNull);

      var sumNull = await db.table('temp_location_temp').sum('id');
      expect(sumNull, isNull);

      // ---- Cenário 3: Mistura de registros com valores null e não nulos ----
      await db.table('temp_location_temp').truncate();

      await db.table('temp_location_temp').insert({
        'id': 1,
        'city': 'City1',
        'street': 'Street1',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': null,
        'city': 'City2',
        'street': 'Street2',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': 3,
        'city': 'City3',
        'street': 'Street3',
        'id_people': 1,
      });

      // Apenas os valores não nulos (1 e 3) devem ser considerados.
      var minMix = await db.table('temp_location_temp').min('id');
      expect(minMix, equals(1));

      var maxMix = await db.table('temp_location_temp').max('id');
      expect(maxMix, equals(3));

      var sumMix = await db.table('temp_location_temp').sum('id');
      expect(sumMix, equals(4));

      var avgMix = await db.table('temp_location_temp').avg('id');
      var avgMixNumeric = avgMix;
      expect(avgMixNumeric, closeTo(2, 0.01));
    });

    test('select different join types', () async {
      // Cria tabelas temporárias para isolar o teste.
      await db.execute('''
    CREATE TEMP TABLE temp_location_temp (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int
    );
  ''');

      await db.execute('''
    CREATE TEMP TABLE people_temp (
      id int,
      name VARCHAR(80),
      profession VARCHAR(80)
    );
  ''');

      // Insere dados em temp_location_temp
      await db.table('temp_location_temp').insert({
        'id': 1,
        'city': 'City1',
        'street': 'Street1',
        'id_people': 1,
      });
      await db.table('temp_location_temp').insert({
        'id': 2,
        'city': 'City2',
        'street': 'Street2',
        'id_people': 2, // Sem correspondente em people_temp
      });

      // Insere dados em people_temp (apenas para id 1)
      await db.table('people_temp').insert({
        'id': 1,
        'name': 'Alice',
        'profession': 'Developer',
      });

      // LEFT JOIN: deve retornar ambos os registros de temp_location_temp;
      // o registro sem match em people_temp terá null no campo people_temp.name.
      var resLeftJoin = await db
          .table('temp_location_temp')
          .leftJoin('people_temp', 'people_temp.id', '=',
              'temp_location_temp.id_people')
          .select([
            'temp_location_temp.id',
            'temp_location_temp.city',
            'people_temp.name'
          ])
          .orderBy('temp_location_temp.id', 'asc')
          .get();

      expect(
          resLeftJoin,
          equals([
            {'id': 1, 'city': 'City1', 'name': 'Alice'},
            {'id': 2, 'city': 'City2', 'name': null},
          ]));

      // RIGHT JOIN: insere um registro extra em people_temp sem correspondente em temp_location_temp.
      await db.table('people_temp').insert({
        'id': 3,
        'name': 'Bob',
        'profession': 'Manager',
      });

      var resRightJoin = await db
          .table('temp_location_temp')
          .rightJoin('people_temp', 'people_temp.id', '=',
              'temp_location_temp.id_people')
          .select([
            'temp_location_temp.id',
            'temp_location_temp.city',
            'people_temp.id as people_id',
            'people_temp.name'
          ])
          .orderBy('people_temp.id', 'asc')
          .get();

      // Espera que apareçam os registros com match e o registro de Bob sem match.
      expect(
          resRightJoin,
          equals([
            {'id': 1, 'city': 'City1', 'people_id': 1, 'name': 'Alice'},
            {'id': null, 'city': null, 'people_id': 3, 'name': 'Bob'},
          ]));

      // CROSS JOIN: o produto cartesiano entre temp_location_temp (2 registros)
      // e people_temp (2 registros) deve resultar em 4 linhas.
      var resCrossJoin = await db
          .table('temp_location_temp')
          .crossJoin('people_temp')
          .select([
            'temp_location_temp.id as loc_id',
            'people_temp.id as people_id'
          ])
          .orderBy('loc_id', 'asc')
          .get();

      expect(resCrossJoin.length, equals(2 * 2)); // 4 linhas
    });

    test('select multiple joins', () async {
      // Cria tabelas temporárias para isolar o teste.
      await db.execute('''
    CREATE TEMP TABLE temp_location_temp (
      id int,
      city VARCHAR(80),
      street VARCHAR(80),
      id_people int,
      id_country int
    );
  ''');
      await db.execute('''
    CREATE TEMP TABLE people_temp (
      id int,
      name VARCHAR(80),
      profession VARCHAR(80)
    );
  ''');
      await db.execute('''
    CREATE TEMP TABLE countries_temp (
      id int,
      name VARCHAR(80)
    );
  ''');

      // Insere dados
      await db.table('temp_location_temp').insert({
        'id': 1,
        'city': 'City1',
        'street': 'Street1',
        'id_people': 1,
        'id_country': 1,
      });
      await db.table('people_temp').insert({
        'id': 1,
        'name': 'Alice',
        'profession': 'Developer',
      });
      await db.table('countries_temp').insert({
        'id': 1,
        'name': 'Brazil',
      });

      var resMultipleJoins = await db
          .table('temp_location_temp')
          .join('people_temp', 'people_temp.id', '=',
              'temp_location_temp.id_people')
          .join('countries_temp', 'countries_temp.id', '=',
              'temp_location_temp.id_country')
          .select([
        'temp_location_temp.id',
        'temp_location_temp.city',
        'people_temp.name',
        'countries_temp.name as country_name'
      ]).get();

      expect(
          resMultipleJoins,
          equals([
            {
              'id': 1,
              'city': 'City1',
              'name': 'Alice',
              'country_name': 'Brazil'
            }
          ]));
    });

    test('select union and unionAll', () async {
      // Preparar uma segunda tabela 'temp_location_backup' similar a 'temp_location'
      await db.execute(
          '''CREATE TABLE "temp_location_backup" AS SELECT * FROM "temp_location";''');

      var query1 = db
          .table('temp_location')
          .select(['city', 'street']).where('city', '=', 'Niteroi');
      var query2 = db
          .table('temp_location_backup')
          .select(['city', 'street']).where('city', '=', 'Rio de Janeiro');

      var resUnion = await query1.union(query2).get();
      expect(resUnion.length, greaterThanOrEqualTo(1)); // Ajuste

      var resUnionAll = await query1.unionAll(query2).get();
      expect(resUnionAll.length, greaterThanOrEqualTo(1)); // Ajuste
    });

    test('select lockForUpdate and sharedLock', () async {
      var queryLockUpdate = db.table('temp_location').lockForUpdate();
      expect(queryLockUpdate.toSql().toLowerCase(), contains('for update'));

      var querySharedLock = db.table('temp_location').sharedLock();
      expect(querySharedLock.toSql().toLowerCase(), contains('for share'));
    });

    test('insert and update with raw expressions', () async {
      await db.table('people').insert({
        'id': 2,
        'name': db.raw("'Maria'"), // Inserir nome como expressão raw
        'profession': 'Designer'
      });

      await db.table('temp_location').where('id', '=', 1).update(
          {'street': db.raw("'UPPER(street)'")}); // Update com expressão raw

      var res = await db.table('temp_location').where('id', '=', 1).first();
      // Verifica que o valor retornado é 'UPPER(street)', ignorando diferenças de case
      expect((res!['street'] as String), equalsIgnoringCase('UPPER(street)'));
    });

    test('delete all records', () async {
      var resDeleteAll = await db.table('temp_location').delete();
      expect(resDeleteAll,
          greaterThanOrEqualTo(0)); // Pode ser 0 se a tabela já estiver vazia
      var countAfterDelete = await db.table('temp_location').count();
      expect(countAfterDelete, 0);
    });

    //end
  });
}
