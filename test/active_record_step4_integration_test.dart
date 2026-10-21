// Active Record: many-to-many, scopes, soft deletes and observers on
// PostgreSQL (four adapters) and MariaDB/MySQL.
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class Member extends Model {
  Member(super.state);

  static final definition = ModelDefinition<Member>(
    table: 'ar4_members',
    create: Member.new,
    softDeletes: true,
    globalScopes: {'tenant': (w) => w.where('ar4_members.tenant', 1)},
  );

  static final roles = BelongsToMany<Member, Role>(
      'roles', () => Role.definition,
      pivotTable: 'ar4_member_role',
      foreignPivotKey: 'member_id',
      relatedPivotKey: 'role_id',
      pivotColumns: ['level']);

  static final posts = HasMany<Member, Post>('posts', () => Post.definition,
      foreignKey: 'member_id');

  /// Local scope.
  static void named(ModelQuery<Member> q) => q.whereLike('name', 'a%');

  int get id => readAttribute<int>('id');
  String get name => readAttribute<String>('name');
  set name(String value) => writeAttribute('name', value);
}

class Role extends Model {
  Role(super.state);
  static final definition =
      ModelDefinition<Role>(table: 'ar4_roles', create: Role.new);
  int get id => readAttribute<int>('id');
  String get name => readAttribute<String>('name');
}

class Post extends Model {
  Post(super.state);
  static final definition = ModelDefinition<Post>(
      table: 'ar4_posts', create: Post.new, softDeletes: true);
  int get id => readAttribute<int>('id');
}

class Recorder extends ModelObserver<Member> {
  final events = <String>[];
  @override
  void saving(Member m) => events.add('saving');
  @override
  void creating(Member m) {
    events.add('creating');
    m.writeAttribute('tenant', 1); // observers may change attributes
  }

  @override
  void created(Member m) => events.add('created:${m.id}');
  @override
  void updating(Member m) => events.add('updating');
  @override
  void updated(Member m) => events.add('updated');
  @override
  void saved(Member m) => events.add('saved');
  @override
  void deleting(Member m) => events.add('deleting');
  @override
  void deleted(Member m) => events.add('deleted');
  @override
  void restoring(Member m) => events.add('restoring');
  @override
  void restored(Member m) => events.add('restored');
}

class Blocker extends ModelObserver<Member> {
  @override
  void deleting(Member m) {
    if (m.name == 'protegido') throw StateError('cannot delete');
  }
}

Map<String, dynamic> _config(String driver) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
      }
    : {
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
      };

const _tables = ['ar4_member_role', 'ar4_posts', 'ar4_roles', 'ar4_members'];

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      final mysql = driver == 'mysql';
      final serial =
          mysql ? 'int AUTO_INCREMENT PRIMARY KEY' : 'serial PRIMARY KEY';
      final timestamp = mysql ? 'datetime' : 'timestamp';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'ar4_$driver');
        db = await manager.getConnection('ar4_$driver');
        for (final t in _tables) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await db
            .execute('CREATE TABLE ar4_members (id $serial, name varchar(20), '
                'tenant int, deleted_at $timestamp NULL)');
        await db.execute(
            'CREATE TABLE ar4_roles (id int PRIMARY KEY, name varchar(20))');
        await db.execute(
            'CREATE TABLE ar4_member_role (member_id int, role_id int, '
            'level int NULL)');
        await db.execute(
            'CREATE TABLE ar4_posts (id int PRIMARY KEY, member_id int, '
            'deleted_at $timestamp NULL)');
        await db.table2('ar4_members').insertMany([
          {'id': 1, 'name': 'ana', 'tenant': 1, 'deleted_at': null},
          {'id': 2, 'name': 'bia', 'tenant': 1, 'deleted_at': null},
          {'id': 3, 'name': 'alex', 'tenant': 2, 'deleted_at': null},
        ]);
        if (!mysql) {
          await db.execute("SELECT setval('ar4_members_id_seq', 3)");
        }
        await db.table2('ar4_roles').insertMany([
          {'id': 10, 'name': 'admin'},
          {'id': 20, 'name': 'editor'},
          {'id': 30, 'name': 'leitor'},
        ]);
        await db.table2('ar4_posts').insertMany([
          {'id': 1, 'member_id': 1, 'deleted_at': null},
          {'id': 2, 'member_id': 1, 'deleted_at': DateTime(2024)},
        ]);
      });

      tearDown(() async {
        for (final t in _tables) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await manager.getDatabaseManager().purge('ar4_$driver');
      });

      test('global and local scopes', () async {
        expect(await Member.definition.query(db).count(), 2,
            reason: 'tenant 2 is out');
        expect(
            await Member.definition
                .query(db)
                .withoutGlobalScope('tenant')
                .count(),
            3);
        expect(
            (await Member.definition.query(db).apply(Member.named).get())
                .map((m) => m.name),
            ['ana'],
            reason: 'alex matches a% but is in tenant 2');
        // An or in the query stays inside the scopes.
        final either = await Member.definition
            .query(db)
            .where('name', 'ana')
            .orWhere('name', 'alex')
            .get();
        expect(either.map((m) => m.name), ['ana']);
      });

      test('soft deletes', () async {
        final bia = (await Member.definition.query(db).find(2))!;
        await bia.delete();
        expect(bia.trashed, isTrue);
        expect(bia.exists, isTrue);
        expect(await Member.definition.query(db).count(), 1);
        expect(await Member.definition.query(db).withTrashed().count(), 2);
        expect(
            (await Member.definition.query(db).onlyTrashed().get()).single.id,
            2);

        await bia.restore();
        expect(bia.trashed, isFalse);
        expect(await Member.definition.query(db).count(), 2);

        expect(await Member.definition.query(db).where('id', 2).delete(), 1);
        expect(await Member.definition.query(db).restore(), 1);
        await bia.forceDelete();
        expect(await Member.definition.query(db).withTrashed().count(), 1);

        // Relations leave out soft-deleted rows too.
        final ana = (await Member.definition.query(db).find(1))!;
        expect((await Member.posts.fetch(ana)).map((p) => p.id), [1]);
      });

      test('many-to-many: attach, pivot, eager load, sync, detach', () async {
        final ana = (await Member.definition.query(db).find(1))!;
        final bia = (await Member.definition.query(db).find(2))!;
        expect(
            await Member.roles.attach(ana, [10, 20], pivot: {'level': 5}), 2);
        await Member.roles.attach(bia, [20]);

        final roles = await Member.roles.fetch(ana);
        expect(roles.map((r) => r.name), ['admin', 'editor']);
        expect(Member.roles.pivot(roles.first)['level'], 5);
        expect(Member.roles.pivot(roles.first)['member_id'], 1);
        expect(roles.first.toMap()['pivot'], isA<Map>());

        final members = await Member.definition
            .query(db)
            .withRelation(Member.roles)
            .orderBy('id')
            .get();
        expect(Member.roles.getLoaded(members[0]).map((r) => r.id), [10, 20]);
        expect(Member.roles.getLoaded(members[1]).map((r) => r.id), [20]);

        final result = await Member.roles.sync(ana, [20, 30]);
        expect(result.attached, [30]);
        expect(result.detached.map((id) => '$id'), ['10']);
        expect((await Member.roles.fetch(ana)).map((r) => r.id), [20, 30]);

        expect(await Member.roles.detach(ana, related: [30]), 1);
        expect(await Member.roles.detach(ana), 1);
        expect(await Member.roles.fetch(ana), isEmpty);
        expect(() => Member.roles.pivot(Role.definition.make(db)),
            throwsStateError);
      });

      test('observers', () async {
        final recorder = Recorder();
        final blocker = Blocker();
        Member.definition
          ..observe(recorder)
          ..observe(blocker);
        try {
          final novo = Member.definition.make(db, {'name': 'novo'});
          await novo.save();
          expect(novo.readAttribute<int>('tenant'), 1);
          novo.name = 'novo2';
          await novo.save();
          await novo.save(); // nothing changed: saving/saved only
          await novo.delete();
          await novo.restore();
          expect(recorder.events, [
            'saving', 'creating', 'created:4', 'saved', //
            'saving', 'updating', 'updated', 'saved', //
            'saving', 'saved', //
            'deleting', 'deleted', 'restoring', 'restored',
          ]);

          final protegido = Member.definition.make(db, {'name': 'protegido'});
          await protegido.save();
          await expectLater(protegido.delete(), throwsStateError);
          expect(protegido.trashed, isFalse);
        } finally {
          Member.definition.unobserve(recorder);
          Member.definition.unobserve(blocker);
        }
      });
    });
  }
}
