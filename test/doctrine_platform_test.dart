import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Table _pedido() {
  final table = Table('pedido');
  table.addColumn('id', 'bigInteger', options: {'autoIncrement': true});
  table.addColumn('cliente_id', 'integer');
  table.addColumn('codigo', 'string', options: {'length': 20});
  table.addColumn('total', 'decimal',
      options: {'precision': 10, 'scale': 2, 'comment': 'valor final'});
  table.addColumn('status', 'string',
      options: {'length': 10, 'default': 'aberto'});
  table.setPrimaryKey(['id']);
  table.addUniqueConstraint(columns: ['codigo'], name: 'pedido_codigo_uniq');
  table.addIndex(columns: ['status'], name: 'pedido_status_idx');
  table.addForeignKey(
      localColumns: ['cliente_id'],
      foreignTableName: 'cliente',
      foreignColumns: ['id'],
      name: 'pedido_cliente_fk',
      options: {
        'onDelete': 'cascade',
        'deferrable': true,
        'deferred': true,
        'match': 'full',
      });
  table.addOption('comment', 'pedidos');
  return table;
}

void main() {
  group('PostgreSQLPlatform', () {
    final platform = PostgreSQLPlatform();

    test('create table with constraints, index, comments and foreign key', () {
      final sql = platform.getCreateTableSQL(_pedido());
      expect(
          sql.first,
          'CREATE TABLE "pedido" ("id" bigserial not null, "cliente_id" integer not null, '
          '"codigo" varchar(20) not null, "total" decimal(10, 2) not null, '
          '"status" varchar(10) not null default \'aberto\', PRIMARY KEY ("id"), '
          'CONSTRAINT "pedido_codigo_uniq" UNIQUE ("codigo"))');
      expect(sql,
          contains('CREATE INDEX "pedido_status_idx" ON "pedido" ("status")'));
      expect(sql, contains('COMMENT ON TABLE "pedido" IS \'pedidos\''));
      expect(sql,
          contains('COMMENT ON COLUMN "pedido"."total" IS \'valor final\''));
      expect(
          sql.last,
          'ALTER TABLE "pedido" ADD CONSTRAINT "pedido_cliente_fk" FOREIGN KEY ("cliente_id") '
          'REFERENCES "cliente" ("id") MATCH FULL ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED');
    });

    test('unlogged tables, sequences, schemas, renames', () {
      final table = Table('cache_tmp')
        ..addColumn('k', 'string', options: {'length': 5})
        ..addOption('unlogged', true);
      expect(platform.getCreateTableSQL(table).single,
          startsWith('CREATE UNLOGGED TABLE "cache_tmp"'));
      expect(
          platform.getCreateSequenceSQL(
              Sequence('protocolo', initialValue: 100, cache: 5)),
          'CREATE SEQUENCE "protocolo" INCREMENT BY 5 MINVALUE 100 START 100');
      expect(platform.getCreateSchemaSQL('vendas'), 'CREATE SCHEMA "vendas"');
      expect(platform.getRenameTableSQL('a', 'b'),
          ['ALTER TABLE "a" RENAME TO "b"']);
      expect(platform.getDropForeignKeySQL('fk', 'pedido'),
          'ALTER TABLE "pedido" DROP CONSTRAINT "fk"');
      expect(platform.getTruncateTableSQL('pedido', cascade: true),
          'TRUNCATE "pedido" CASCADE');
    });

    test('schema: namespaces, sequences and tables; drop in reverse', () {
      final schema = Schema();
      final cliente = schema.createTable('cliente');
      cliente.addColumn('id', 'integer', options: {'autoIncrement': true});
      cliente.setPrimaryKey(['id']);
      final venda = schema.createTable('vendas.venda');
      venda.addColumn('id', 'integer');
      venda.addColumn('cliente_id', 'integer');
      venda.addForeignKey(
          localColumns: ['cliente_id'],
          foreignTableName: 'cliente',
          foreignColumns: ['id'],
          name: 'venda_cliente_fk');
      schema.createSequence('protocolo');

      expect(schema.getNamespaces(), ['vendas']);
      expect(schema.hasTable('public.cliente'), isTrue);
      expect(schema.getTable('vendas.venda').getNamespaceName(), 'vendas');

      final sql = schema.toSql(platform);
      expect(sql.first, 'CREATE SCHEMA "vendas"');
      expect(sql[1], startsWith('CREATE SEQUENCE "protocolo"'));
      expect(sql, contains(startsWith('CREATE TABLE "vendas"."venda"')));
      // Foreign keys after every table.
      expect(
          sql.last, startsWith('ALTER TABLE "vendas"."venda" ADD CONSTRAINT'));

      final drop = schema.toDropSql(platform);
      expect(drop.first,
          'ALTER TABLE "vendas"."venda" DROP CONSTRAINT "venda_cliente_fk"');
      expect(drop.last, 'DROP SEQUENCE "protocolo"');
    });

    test('compareSchemas -> getAlterSchemaSQL', () {
      final old = Schema();
      old.createTable('a').addColumn('id', 'integer');
      old.createTable('velha').addColumn('id', 'integer');

      final novo = Schema();
      novo.createTable('a')
        ..addColumn('id', 'integer')
        ..addColumn('nome', 'string',
            options: {'length': 30, 'nullable': true});
      novo.createTable('nova').addColumn('id', 'integer');

      final diff = Comparator().compareSchemas(old, novo);
      expect(diff.getCreatedTables().map((t) => t.getName()), ['nova']);
      expect(diff.getDroppedTables().map((t) => t.getName()), ['velha']);
      expect(diff.getAlteredTables(), hasLength(1));

      final sql = platform.getAlterSchemaSQL(diff);
      expect(sql, [
        'CREATE TABLE "nova" ("id" integer not null)',
        'alter table "a" add column "nome" varchar(30) null',
        'DROP TABLE "velha"',
      ]);
      expect(Comparator().compareSchemas(novo, novo.clone()).isEmpty(), isTrue);
    });

    test('types, expressions and keywords', () {
      expect(platform.getIntegerTypeDeclarationSQL({'autoincrement': true}),
          'serial');
      expect(
          platform.getStringTypeDeclarationSQL({'length': 12}), 'varchar(12)');
      expect(() => platform.getStringTypeDeclarationSQL({}),
          throwsA(isA<ColumnLengthRequiredException>()));
      expect(platform.getDoctrineTypeMapping('int8'), 'biginteger');
      expect(
          platform.getLocateExpression('nome', "'a'"), "POSITION('a' IN nome)");
      expect(platform.getDateAddQuartersExpression('d', '2'),
          "(d + ((2 * 3) || ' MONTH')::interval)");
      expect(platform.getReservedKeywordsList().isKeyword('select'), isTrue);
      expect(platform.quoteIdentifier('vendas.pedido'), '"vendas"."pedido"');
      expect(
          platform.getSetTransactionIsolationSQL(
              TransactionIsolationLevel.SERIALIZABLE),
          'SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE');
    });
  });

  group('MySQLPlatform', () {
    final platform = MySQLPlatform();

    test('create table: inline comments, table options, no deferrable', () {
      final sql = platform.getCreateTableSQL(_pedido());
      expect(
          sql.first,
          'CREATE TABLE `pedido` (`id` bigint not null auto_increment, '
          '`cliente_id` int not null, `codigo` varchar(20) not null, '
          "`total` decimal(10, 2) not null comment 'valor final', "
          "`status` varchar(10) not null default 'aberto', PRIMARY KEY (`id`), "
          "CONSTRAINT `pedido_codigo_uniq` UNIQUE (`codigo`)) COMMENT = 'pedidos'");
      expect(
          sql.last,
          'ALTER TABLE `pedido` ADD CONSTRAINT `pedido_cliente_fk` FOREIGN KEY (`cliente_id`) '
          'REFERENCES `cliente` (`id`) ON DELETE CASCADE');
      expect(sql.where((s) => s.startsWith('COMMENT ON')), isEmpty);
    });

    test('drops, renames, expressions', () {
      expect(platform.getDropForeignKeySQL('fk', 'pedido'),
          'ALTER TABLE `pedido` DROP FOREIGN KEY `fk`');
      expect(platform.getDropIndexSQL('idx', 'pedido'),
          'DROP INDEX `idx` ON `pedido`');
      expect(platform.getRenameTableSQL('a', 'b'), ['RENAME TABLE `a` TO `b`']);
      expect(
          platform.getIntegerTypeDeclarationSQL(
              {'autoincrement': true, 'unsigned': true}),
          'int UNSIGNED AUTO_INCREMENT');
      expect(platform.getDateAddDaysExpression('d', '3'),
          'DATE_ADD(d, INTERVAL 3 DAY)');
      expect(platform.getConcatExpression(['a', 'b']), 'CONCAT(a, b)');
      expect(platform.convertBooleans([true, false]), [1, 0]);
      expect(() => platform.getCreateSequenceSQL(Sequence('s')),
          throwsA(isA<NotSupported>()));
      expect(MariaDBPlatform().getReservedKeywordsList().isKeyword('select'),
          isTrue);
    });
  });
}
