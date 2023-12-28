import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

/// test PostgresPDO
/// config['driver_implementation'] == 'postgres'
/// run: dart test .\test\postgres_query_test.dart -j 1 --chain-stack-traces --name 'update simple'
void main() {
  late Connection db;
  setUp(() async {
    var manager = Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'postgres',
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'usermd5',
      'password': 's1sadm1n',
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
  });
}
