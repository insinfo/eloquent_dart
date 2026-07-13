import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/schema/grammars/schema_mysql_grammar.dart';
import 'package:test/test.dart';

class FakePdo extends PDOInterface {
  @override
  PDOConfig config;

  FakePdo(this.config) {
    pdoInstance = this;
  }

  @override
  Future<PDOInterface> connect() async => this;

  @override
  Future close() async {}

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async => 0;

  @override
  PDOConfig getConfig() => config;

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) async =>
      PDOResults([], 0);

  @override
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),
          [int? timeoutInSeconds]) =>
      operation(this);
}

void main() {
  group('SchemaGrammar Doctrine diff helpers', () {
    late SchemaGrammar grammar;

    setUp(() {
      grammar = SchemaPostgresGrammar();
    });

    test('Column stores and renames asset names correctly', () {
      final column = Column('name', 'string');

      expect(column.getName(), 'name');

      column.setName('full_name');

      expect(column.getName(), 'full_name');
      expect(column.getOriginalName(), 'full_name');
    });

    test('maps Laravel fluent column metadata to Doctrine column options', () {
      expect(grammar.getDoctrineColumnType('bigInteger'), 'bigint');
      expect(grammar.getDoctrineColumnType('mediumText'), 'text');
      expect(grammar.getDoctrineColumnType('binary'), 'blob');
      expect(grammar.calculateDoctrineTextLength('longText'), 16777216);
      expect(grammar.mapFluentOptionToDoctrine('nullable'), 'notnull');
      expect(grammar.mapFluentValueToDoctrine('notnull', true), isFalse);
    });

    test('builds a renamed TableDiff from an in-memory Doctrine table', () {
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      final command = Fluent({'from': 'name', 'to': 'full_name'});

      final diff = grammar.getRenamedDiff(
        blueprint,
        command,
        table.getColumn('name'),
        table,
      ) as TableDiff;

      expect(diff.name, 'users');
      expect(diff.oldTable, same(table));
      expect(diff.renamedColumns, {'name': 'full_name'});
    });

    test('applies changed Blueprint columns to a cloned Doctrine table', () {
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      blueprint.string('name', 100);
      blueprint.nullable();
      blueprint.change();

      final changedTable =
          grammar.getTableWithColumnChanges(blueprint, table) as Table;
      final changedColumn = changedTable.getColumn('name');

      expect(changedTable, isNot(same(table)));
      expect(table.getColumn('name').length, 255);
      expect(changedColumn.length, 100);
      expect(changedColumn.notnull, isFalse);
    });

    test('detects changed columns from Blueprint and Doctrine table fixture',
        () {
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      blueprint.text('name');
      blueprint.change();

      final diff = grammar.getChangedDiff(blueprint, table) as TableDiff;

      expect(diff.changedColumns, contains('name'));
      expect(diff.changedColumns['name']!.oldColumn.type, 'string');
      expect(diff.changedColumns['name']!.newColumn.type, 'text');
      expect(diff.changedColumns['name']!.newColumn.length, 256);
    });

    test('compiles PostgreSQL SQL from TableDiff column changes', () {
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      blueprint.text('name');
      blueprint.change();

      final diff = grammar.getChangedDiff(blueprint, table) as TableDiff;

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter table "users" alter column "name" type text',
      ]);
    });

    test('compiles PostgreSQL SQL from TableDiff renamed columns', () {
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      final command = Fluent({'from': 'name', 'to': 'full_name'});
      final diff = grammar.getRenamedDiff(
        blueprint,
        command,
        table.getColumn('name'),
        table,
      ) as TableDiff;

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter table "users" rename column "name" to "full_name"',
      ]);
    });

    test('compiles MySQL SQL from TableDiff column changes', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'users',
        columns: [
          Column('name', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('users');
      blueprint.string('name', 100);
      blueprint.nullable();
      blueprint.change();

      final diff = mysqlGrammar.getChangedDiff(blueprint, table) as TableDiff;

      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `users` change `name` `name` varchar(100) null',
      ]);
    });

    test('MySQL compileRenameColumn no longer uses placeholder definition', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final blueprint = Blueprint('users');
      final command = Fluent({'from': 'name', 'to': 'full_name'});

      expect(
        mysqlGrammar.compileRenameColumn(
          blueprint,
          command,
          Connection(
            FakePdo(PDOConfig(
              driver: 'mysql',
              host: 'localhost',
              database: 'app',
            )),
          ),
        ),
        ['alter table `users` rename column `name` to `full_name`'],
      );
    });

    test('compiles PostgreSQL SQL from TableDiff indexes and constraints', () {
      final table = Table(
        'posts',
        columns: [
          Column('id', 'integer'),
          Column('user_id', 'integer'),
          Column('slug', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        addedIndexes: {
          'idx_posts_slug': Index(
            name: 'idx_posts_slug',
            columns: ['slug'],
          ),
        },
        addedUniqueConstraints: {
          'uniq_posts_slug': UniqueConstraint(
            name: 'uniq_posts_slug',
            columns: ['slug'],
          ),
        },
        addedForeignKeys: {
          'fk_posts_user_id': ForeignKeyConstraint(
            name: 'fk_posts_user_id',
            localColumns: ['user_id'],
            foreignTableName: 'users',
            foreignColumns: ['id'],
            options: {'onDelete': 'cascade'},
          ),
        },
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter table "posts" add constraint "uniq_posts_slug" unique ("slug")',
        'create index "idx_posts_slug" on "posts" ("slug")',
        'alter table "posts" add constraint "fk_posts_user_id" foreign key ("user_id") references "users" ("id") on delete CASCADE',
      ]);
    });

    test('compiles MySQL SQL from TableDiff indexes and constraints', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('id', 'integer'),
          Column('user_id', 'integer'),
          Column('slug', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        addedIndexes: {
          'idx_posts_slug': Index(
            name: 'idx_posts_slug',
            columns: ['slug'],
          ),
        },
        addedUniqueConstraints: {
          'uniq_posts_slug': UniqueConstraint(
            name: 'uniq_posts_slug',
            columns: ['slug'],
          ),
        },
        addedForeignKeys: {
          'fk_posts_user_id': ForeignKeyConstraint(
            name: 'fk_posts_user_id',
            localColumns: ['user_id'],
            foreignTableName: 'users',
            foreignColumns: ['id'],
            options: {'onDelete': 'cascade'},
          ),
        },
      );

      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` add unique `uniq_posts_slug` (`slug`), add index `idx_posts_slug` (`slug`), add constraint `fk_posts_user_id` foreign key (`user_id`) references `users` (`id`) on delete CASCADE',
      ]);
    });

    test('compiles drop SQL from TableDiff indexes and foreign keys', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('id', 'integer'),
          Column('user_id', 'integer'),
          Column('slug', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        droppedIndexes: {
          'idx_posts_slug': Index(
            name: 'idx_posts_slug',
            columns: ['slug'],
          ),
        },
        droppedForeignKeys: {
          'fk_posts_user_id': ForeignKeyConstraint(
            name: 'fk_posts_user_id',
            localColumns: ['user_id'],
            foreignTableName: 'users',
            foreignColumns: ['id'],
          ),
        },
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter table "posts" drop constraint "fk_posts_user_id"',
        'drop index "idx_posts_slug"',
      ]);
      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` drop foreign key `fk_posts_user_id`, drop index `idx_posts_slug`',
      ]);
    });

    test('compiles renamed indexes from TableDiff', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('slug', 'string', options: {'length': 255}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        renamedIndexes: {'idx_posts_slug': 'idx_posts_slug_new'},
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter index "idx_posts_slug" rename to "idx_posts_slug_new"',
      ]);
      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` rename index `idx_posts_slug` to `idx_posts_slug_new`',
      ]);
    });

    test('compiles changed indexes from TableDiff as drop and create', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('slug', 'string', options: {'length': 255}),
          Column('status', 'string', options: {'length': 20}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        changedIndexes: {
          'idx_posts_slug': Index(
            name: 'idx_posts_slug',
            columns: ['slug', 'status'],
          ),
        },
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'drop index "idx_posts_slug"',
        'create index "idx_posts_slug" on "posts" ("slug", "status")',
      ]);
      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` drop index `idx_posts_slug`, add index `idx_posts_slug` (`slug`, `status`)',
      ]);
    });

    test('compiles changed unique constraints from TableDiff as drop and add',
        () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('slug', 'string', options: {'length': 255}),
          Column('status', 'string', options: {'length': 20}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        changedUniqueConstraints: {
          'uniq_posts_slug': UniqueConstraint(
            name: 'uniq_posts_slug',
            columns: ['slug', 'status'],
          ),
        },
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'alter table "posts" drop constraint "uniq_posts_slug"',
        'alter table "posts" add constraint "uniq_posts_slug" unique ("slug", "status")',
      ]);
      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` drop index `uniq_posts_slug`, add unique `uniq_posts_slug` (`slug`, `status`)',
      ]);
    });

    test('Doctrine Index fulfillment follows DBAL uniqueness semantics', () {
      final plain = Index(name: 'idx_slug', columns: ['slug']);
      final unique = Index(
        name: 'uniq_slug',
        columns: ['slug'],
        isUnique: true,
      );
      final primary = Index(
        name: 'primary',
        columns: ['slug'],
        isUnique: true,
        isPrimary: true,
      );

      expect(plain.isFulfilledBy(unique), isTrue);
      expect(plain.isFulfilledBy(primary), isTrue);
      expect(unique.isFulfilledBy(plain), isFalse);
      expect(primary.isFulfilledBy(unique), isFalse);
    });

    test('Doctrine Index handles partial options, flags and quoted positions',
        () {
      final withoutWhere = Index(
        name: 'idx_without',
        columns: ['`slug`', '`status`'],
        isUnique: true,
      );
      final partial = Index(
        name: 'idx_partial',
        columns: ['`slug`', '`status`'],
        isUnique: true,
        options: {'WHERE': 'slug IS NOT NULL'},
      );
      final samePartial = Index(
        name: 'idx_same_partial',
        columns: ['slug', 'status'],
        isUnique: true,
        options: {'where': 'slug IS NOT NULL'},
      );

      expect(partial.hasOption('where'), isTrue);
      expect(partial.hasOption('WHERE'), isTrue);
      expect(partial.getOption('WHERE'), 'slug IS NOT NULL');
      expect(partial.isFulfilledBy(withoutWhere), isFalse);
      expect(withoutWhere.isFulfilledBy(partial), isFalse);
      expect(partial.isFulfilledBy(samePartial), isTrue);
      expect(partial.overrules(samePartial), isTrue);
      expect(withoutWhere.hasColumnAtPosition('slug', 0), isTrue);
      expect(withoutWhere.hasColumnAtPosition('status', 1), isTrue);
      expect(withoutWhere.hasColumnAtPosition('slug', 1), isFalse);

      withoutWhere.addFlag('CLUSTERED');
      expect(withoutWhere.hasFlag('clustered'), isTrue);
      expect(withoutWhere.isClustered(), isTrue);

      withoutWhere.removeFlag('clustered');
      expect(withoutWhere.hasFlag('clustered'), isFalse);
      expect(withoutWhere.isClustered(), isFalse);
    });

    test('Doctrine Index compares sparse column lengths like DBAL', () {
      final indexWithListLengths = Index(
        name: 'idx_list_lengths',
        columns: ['slug', 'status'],
        options: {
          'lengths': [null, 32],
        },
      );
      final indexWithMapLengths = Index(
        name: 'idx_map_lengths',
        columns: ['slug', 'status'],
        options: {
          'lengths': {1: 32},
        },
      );
      final indexWithDifferentPosition = Index(
        name: 'idx_different_position',
        columns: ['slug', 'status'],
        options: {
          'lengths': {0: 32},
        },
      );

      expect(indexWithListLengths.isFulfilledBy(indexWithMapLengths), isTrue);
      expect(indexWithMapLengths.isFulfilledBy(indexWithListLengths), isTrue);
      expect(
        indexWithListLengths.isFulfilledBy(indexWithDifferentPosition),
        isFalse,
      );
    });

    test('compiles partial and length-aware indexes by platform', () {
      final mysqlGrammar = SchemaMySqlGrammar();
      final table = Table(
        'posts',
        columns: [
          Column('slug', 'string', options: {'length': 255}),
          Column('status', 'string', options: {'length': 20}),
        ],
      );
      final blueprint = Blueprint('posts');
      final diff = TableDiff(
        name: 'posts',
        oldTable: table,
        addedIndexes: {
          'idx_posts_slug_partial': Index(
            name: 'idx_posts_slug_partial',
            columns: ['slug', 'status'],
            options: {
              'where': 'slug IS NOT NULL',
              'lengths': [64, null],
            },
          ),
        },
      );

      expect(grammar.compileTableDiff(diff, blueprint), [
        'create index "idx_posts_slug_partial" on "posts" ("slug", "status") where slug IS NOT NULL',
      ]);
      expect(mysqlGrammar.compileTableDiff(diff, blueprint), [
        'alter table `posts` add index `idx_posts_slug_partial` (`slug`(64), `status`)',
      ]);
    });
  });
}
