// AttributeModel (columns in a map, typed getters/setters) on PostgreSQL
// (four adapters) and MariaDB/MySQL, plus changes inside mutable values for
// both model styles. Requires localhost:5432 / 3306, database `banco_teste`,
// dart/dart.
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class Account extends AttributeModel<Account> {
  static final definition = ModelDefinition<Account>(
    table: 'ar5_accounts',
    create: Account.new,
    timestamps: true,
    casts: {'active': Casts.boolean},
    fillable: ['name', 'note'],
    hidden: ['note'],
  );

  @override
  ModelDefinition<Account> get modelDefinition => definition;

  static ModelQuery<Account> query(Connection db) => definition.query(db);

  static final entriesRelation = HasMany<Account, Entry>(
      'entries', () => Entry.definition,
      foreignKey: 'account_id');

  /// The loaded relation, read from the instance.
  List<Entry> get entries => entriesRelation.getLoaded(this);

  int? get id => getAttribute<int?>('id');
  String get name => getAttribute<String>('name');
  set name(String value) => setAttribute('name', value);
  bool? get active => getAttribute<bool?>('active');
  set active(bool? value) => setAttribute('active', value);
  String? get note => getAttribute<String?>('note');
  set note(String? value) => setAttribute('note', value);
}

/// A scope as an extension: `Account.query(db).onlyActive()`.
extension AccountScopes on ModelQuery<Account> {
  ModelQuery<Account> onlyActive() => where('active', true);
}

class Entry extends AttributeModel<Entry> {
  static final definition =
      ModelDefinition<Entry>(table: 'ar5_entries', create: Entry.new);

  @override
  ModelDefinition<Entry> get modelDefinition => definition;

  int? get id => getAttribute<int?>('id');
  int get accountId => getAttribute<int>('account_id');
  set accountId(int value) => setAttribute('account_id', value);
  int get amount => getAttribute<int>('amount');
  set amount(int value) => setAttribute('amount', value);
}

/// A field model with a mutable value.
class Tagged extends Model<Tagged> {
  static final definition =
      ModelDefinition<Tagged>(table: 'ar5_tagged', create: Tagged.new);

  @override
  ModelDefinition<Tagged> get modelDefinition => definition;

  int? id;
  List<String> tags = [];

  @override
  Map<String, dynamic> toMap() => {'id': id, 'tags': tags};

  @override
  void fill(Map<String, dynamic> row) {
    id = row['id'] as int?;
    tags = (row['tags'] as List).cast<String>().toList();
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

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'ar5_$driver');
        db = await manager.getConnection('ar5_$driver');
        await db.execute('DROP TABLE IF EXISTS ar5_entries');
        await db.execute('DROP TABLE IF EXISTS ar5_accounts');
        final serial =
            mysql ? 'int AUTO_INCREMENT PRIMARY KEY' : 'serial PRIMARY KEY';
        await db.execute('CREATE TABLE ar5_accounts (id $serial, '
            'name varchar(40), '
            'active ${mysql ? 'tinyint(1) DEFAULT 1' : 'boolean DEFAULT true'}, '
            "note varchar(20) NULL DEFAULT 'padrao', "
            'created_at ${mysql ? 'datetime' : 'timestamp'} NULL, '
            'updated_at ${mysql ? 'datetime' : 'timestamp'} NULL)');
        await db.execute('CREATE TABLE ar5_entries (id $serial, '
            'account_id int, amount int)');
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS ar5_entries');
        await db.execute('DROP TABLE IF EXISTS ar5_accounts');
        await manager.getDatabaseManager().purge('ar5_$driver');
      });

      test('insert: an unset attribute gets the default, null is written',
          () async {
        final ana = Account()..name = 'Ana';
        await ana.save(using: db);
        final bia = Account()
          ..name = 'Bia'
          ..note = null;
        await bia.save(using: db);
        expect([ana.id, bia.id], [1, 2]);
        if (!mysql) {
          expect(ana.active, isTrue, reason: 'returning * reads defaults');
        }

        final rows = await Account.query(db).orderBy('id').get();
        expect(rows.map((a) => a.note), ['padrao', null]);
        expect(rows.map((a) => a.active), [true, true]);
        expect(rows.first.getAttribute<DateTime?>('created_at'), isNotNull);
      });

      test('a column that was not selected throws; save writes the changes',
          () async {
        final ana = Account()
          ..name = 'Ana'
          ..active = false;
        await ana.save(using: db);

        final partial = (await Account.query(db)
            .select(['id', 'name'])
            .where('id', ana.id!)
            .first())!;
        expect(() => partial.active, throwsStateError,
            reason: 'not selected is not null');
        expect(partial.hasAttribute('active'), isFalse);
        partial.name = 'Ana Maria';
        expect(partial.getDirty().keys, ['name']);
        await partial.save();

        final again = (await Account.query(db).find(ana.id!))!;
        expect(again.name, 'Ana Maria');
        expect(again.active, isFalse, reason: 'untouched column kept');
        expect(again.isDirty(), isFalse);
        expect(() => Account().name, throwsStateError,
            reason: 'a non-nullable attribute that was never set');
      });

      test('assign, hidden, an extension scope and an instance relation',
          () async {
        final ana = Account.definition.make(db)
          ..assign({'name': 'Ana', 'note': 'vip', 'id': 99, 'active': false});
        expect(ana.attributes, {'name': 'Ana', 'note': 'vip'});
        await ana.save();
        expect(ana.id, 1, reason: 'id is not fillable');
        await (Account()
              ..name = 'Bia'
              ..active = false)
            .save(using: db);
        for (final amount in [10, 20]) {
          await (Entry()
                ..accountId = ana.id!
                ..amount = amount)
              .save(using: db);
        }

        final active = await Account.query(db)
            .onlyActive()
            .withRelation(Account.entriesRelation)
            .orderBy('id')
            .get();
        expect(active.map((a) => a.name), ['Ana']);
        expect(active.single.entries.map((e) => e.amount), [10, 20]);

        final json = jsonDecode(jsonEncode(active.single)) as Map;
        expect(json.containsKey('note'), isFalse, reason: 'hidden');
        expect(json['entries'], hasLength(2));
        expect(json['active'], isTrue);
      });

      test('getDirty sees changes inside mutable values', () async {
        final account = Account.definition.hydrate(db, {
          'id': 1,
          'name': 'x',
          'tags': ['a'],
        });
        account.getAttribute<List>('tags').add('b');
        expect(account.getDirty().keys, ['tags']);

        final tagged = Tagged.definition.hydrate(db, {
          'id': 1,
          'tags': ['a'],
        });
        expect(tagged.isDirty(), isFalse);
        tagged.tags.add('b');
        expect(tagged.getDirty(), {
          'tags': ['a', 'b'],
        });
      });
    });
  }
}
