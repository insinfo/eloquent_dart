//lib\src\schema\grammars\schema_postgres_grammar.dart

import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart'; // Import for @protected

/// Gramática específica do PostgreSQL para operações de Schema.
/// Traduz comandos do Blueprint para SQL compatível com PostgreSQL.
class SchemaPostgresGrammar extends SchemaGrammar {
  /// Os modificadores de coluna suportados especificamente por esta gramática.
  @override
  final List<String> modifiers = const [
    // 'Incrementing', // Tratado pelo tipo serial
    'Nullable',
    'Default',
    'Collate', // Suportado
    'VirtualAs', // Suportado como GENERATED ... STORED (fallback)
    'StoredAs', // Suportado como GENERATED ... STORED
    'Comment', // Requer comando separado
    'Srid' // Tratado no tipo GIS
    // Não suportados: Unsigned, First, After, Charset
  ];

  /// Os tipos de coluna que mapeiam para tipos auto-incremento (SERIAL) no PostgreSQL.
  @override
  final List<String> serials = const [
    'bigInteger',
    'integer',
    'mediumInteger',
    'smallInteger',
    'tinyInteger',
  ];

  SchemaPostgresGrammar() : super();

  /// Ajusta a inicialização dos modificadores para PostgreSQL.
  @override
  @protected
  Map<String, Function(Blueprint, Fluent)> initializeModifierCompilers() {
    return {
      'Nullable': (b, c) => modifyNullable(b, c),
      'Default': (b, c) => modifyDefault(b, c),
      'Collate': (b, c) => modifyCollate(b, c),
      'VirtualAs': (b, c) => modifyVirtualAs(b, c),
      'StoredAs': (b, c) => modifyStoredAs(b, c),
      'Comment': (b, c) => modifyComment(b, c), // Retorna null
      'Srid': (b, c) => modifySrid(b, c), // Retorna null
    };
  }

  /// Compila a query para determinar se uma tabela existe.
  @override
  String compileTableExists() {
    return 'select 1 from information_schema.tables where table_schema = ? and table_name = ? limit 1';
  }

  /// Compila a query para determinar a lista de colunas.
  @override
  String compileColumnExists(String table) {
    return "select column_name from information_schema.columns where table_schema = ? and table_name = ?";
  }

  // --- Métodos de Compilação de Comandos (Retornam List<String>) ---

  /// Compila um comando de chave primária (ALTER TABLE ... ADD PRIMARY KEY).
  @override
  List<String> compilePrimary(Blueprint blueprint, Fluent command) {
    final columns = columnize(command['columns'] as List);
    // PG usa nome padrão tablename_pkey, ignora nome customizado
    return ['alter table ${wrapTable(blueprint)} add primary key ($columns)'];
  }

  /// Compila um comando de índice único (ALTER TABLE ... ADD CONSTRAINT ... UNIQUE).
  @override
  List<String> compileUnique(Blueprint blueprint, Fluent command) {
    final columns = columnize(command['columns'] as List);
    final indexName = wrap(command['index']); // Nome é obrigatório
    return [
      'alter table ${wrapTable(blueprint)} add constraint $indexName unique ($columns)'
    ];
  }

  /// Compila um comando de índice (CREATE INDEX).
  @override
  List<String> compileIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final table = wrapTable(blueprint);
    final columns = columnize(command['columns'] as List);
    String using = '';
    // Adicionar lógica para 'algorithm'/'type' se presente no command Fluent
    // if (command['algorithm'] != null) { using = ' using ${command['algorithm']}'; }
    return ['create index $indexName on $table$using ($columns)'];
  }

  /// Compila um comando de índice espacial (CREATE INDEX ... USING GIST/SPGIST).
  @override
  List<String> compileSpatialIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final table = wrapTable(blueprint);
    final columns = columnize(command['columns'] as List);
    // Assume GIST por padrão, pode ser configurado via 'algorithm' no Fluent
    final algorithm = command['algorithm'] ?? 'gist';
    return ['create index $indexName on $table using $algorithm ($columns)'];
  }

  /// Compila um comando de chave estrangeira (ALTER TABLE ... ADD CONSTRAINT).
  @override
  List<String> compileForeign(Blueprint blueprint, Fluent command) {
    // Reutiliza a implementação da classe base que já retorna List<String>
    // e tem a sintaxe padrão SQL correta para ADD CONSTRAINT FOREIGN KEY.
    return super.compileForeign(blueprint, command);
  }

  /// Compila um comando para dropar uma chave primária (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropPrimary(Blueprint blueprint, Fluent command) {
    final tableName = blueprint.getTable();
    final pkName = wrap('${tableName}_pkey'); // Nome padrão PG
    return ['alter table ${wrapTable(blueprint)} drop constraint $pkName'];
  }

  /// Compila um comando para dropar um índice único (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropUnique(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    return ['alter table ${wrapTable(blueprint)} drop constraint $indexName'];
  }

  /// Compila um comando para dropar um índice (DROP INDEX ...).
  @override
  List<String> compileDropIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    // Adiciona IF EXISTS para segurança
    return ['drop index if exists $indexName'];
  }

  /// Compila um comando para dropar um índice espacial (DROP INDEX ...).
  @override
  List<String> compileDropSpatialIndex(Blueprint blueprint, Fluent command) {
    return compileDropIndex(blueprint, command); // Mesma sintaxe no PG
  }

  /// Compila um comando para dropar uma chave estrangeira (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropForeign(Blueprint blueprint, Fluent command) {
    // Reutiliza a implementação da classe base que já retorna List<String>
    // e tem a sintaxe correta para DROP CONSTRAINT.
    return super.compileDropForeign(blueprint, command);
  }

  /// Compila um comando para renomear um índice (ALTER INDEX ... RENAME TO ...).
  @override
  List<String> compileRenameIndex(Blueprint blueprint, Fluent command) {
    final from = wrap(command['from'] as String);
    final to = wrap(command['to'] as String);
    return ['alter index $from rename to $to'];
  }

  /// Compila um comando para renomear uma coluna (ALTER TABLE ... RENAME COLUMN ... TO ...).
  @override
  List<String> compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    final table = wrapTable(blueprint);
    final from = wrap(command['from'] as String);
    final to = wrap(command['to'] as String);
    return ['alter table $table rename column $from to $to'];
  }

  /// Compila um comando para modificar uma coluna.
  @override
  List<String> compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    // (Implementação complexa anterior mantida)
    print(
        "Warning: compileChange in PostgreSQL might generate multiple ALTER statements and requires careful handling of type changes and defaults.");
    final table = wrapTable(blueprint);
    final List<String> statements = [];

    for (final column in blueprint.getChangedColumns()) {
      final colName = wrap(column);
      String? baseType = getType(column);

      // 1. Alterar tipo
      if (baseType != null) {
        // Idealmente, precisaria de introspecção para adicionar USING clause se necessário
        print(
            "Warning: Changing column type for '$colName' without introspection. Data conversion might be needed (USING clause).");
        statements
            .add('alter table $table alter column $colName type $baseType');
      }

      // 2. Alterar Collation
      final String? collateMod = modifyCollate(blueprint, column);
      if (collateMod != null && collateMod.isNotEmpty) {
        // Extrai o nome da collation
        final collationName = collateMod.replaceFirst(' collate ', '').trim();
        statements.add(
            'alter table $table alter column $colName set collation $collationName');
      }

      // 3. Alterar Nullability
      final String? nullMod = modifyNullable(blueprint, column);
      if (nullMod != null) {
        if (nullMod.trim() == 'null') {
          statements
              .add('alter table $table alter column $colName drop not null');
        } else if (nullMod.trim() == 'not null') {
          statements
              .add('alter table $table alter column $colName set not null');
        }
      }

      // 4. Alterar Default
      if (column.attributes.containsKey('default')) {
        final String? defaultMod = modifyDefault(blueprint, column);
        if (defaultMod != null && defaultMod.isNotEmpty) {
          final defaultValue = defaultMod.replaceFirst(' default ', '').trim();
          if (defaultValue == 'NULL') {
            statements
                .add('alter table $table alter column $colName drop default');
          } else {
            statements.add(
                'alter table $table alter column $colName set$defaultMod'); // SET DEFAULT valor
          }
        } else {
          statements
              .add('alter table $table alter column $colName drop default');
        }
      }
      // Comentário não é tratado aqui, precisaria de COMMENT ON
    }
    return statements;
  }

  /// Compila o comando SQL para habilitar restrições de chave estrangeira no PostgreSQL.
  @override
  List<String> compileEnableForeignKeyConstraints() {
    // Esta abordagem afeta toda a sessão e pode ter implicações na replicação.
    // Alternativa: ALTER TABLE ... ENABLE TRIGGER USER; (se triggers forem usados)
    // Alternativa: SET CONSTRAINTS ALL IMMEDIATE; (afeta a transação atual)
    return ['SET session_replication_role = DEFAULT;'];
  }

  /// Compila o comando SQL para desabilitar restrições de chave estrangeira no PostgreSQL.
  @override
  List<String> compileDisableForeignKeyConstraints() {
    // Esta abordagem afeta toda a sessão e pode ter implicações na replicação.
    // Alternativa: ALTER TABLE ... DISABLE TRIGGER USER;
    // Alternativa: SET CONSTRAINTS ALL DEFERRED;
    return ['SET session_replication_role = replica;'];
  }

  // --- Implementações de Tipos de Coluna para PostgreSQL ---
  // (Mantidos como estavam na revisão anterior)
  @override
  String typeChar(Fluent column) => 'char(${column['length']})';
  @override
  String typeString(Fluent column) => 'varchar(${column['length']})';
  @override
  String typeText(Fluent column) => 'text';
  @override
  String typeMediumText(Fluent column) => 'text';
  @override
  String typeLongText(Fluent column) => 'text';
  @override
  String typeInteger(Fluent column) =>
      column['autoIncrement'] == true ? 'serial' : 'integer';
  @override
  String typeBigInteger(Fluent column) =>
      column['autoIncrement'] == true ? 'bigserial' : 'bigint';
  @override
  String typeMediumInteger(Fluent column) =>
      column['autoIncrement'] == true ? 'serial' : 'integer';
  @override
  String typeSmallInteger(Fluent column) =>
      column['autoIncrement'] == true ? 'smallserial' : 'smallint';
  @override
  String typeTinyInteger(Fluent column) =>
      column['autoIncrement'] == true ? 'smallserial' : 'smallint';
  @override
  String typeFloat(Fluent column) => 'double precision';
  @override
  String typeDouble(Fluent column) => 'double precision';
  @override
  String typeDecimal(Fluent column) =>
      'decimal(${column['total']}, ${column['places']})';
  @override
  String typeUnsignedDecimal(Fluent column) {
    print("Warning: PostgreSQL does not support UNSIGNED columns.");
    return typeDecimal(column);
  }

  @override
  String typeBoolean(Fluent column) => 'boolean';
  @override
  String typeEnum(Fluent column) {
    final allowed = (column['allowed'] as List)
        .map((e) => "'${e.toString().replaceAll("'", "''")}'")
        .join(', ');
    final colName = wrap(column['name'] as String);
    return 'varchar(255) check ($colName::text in ($allowed))';
  }

  @override
  String typeJson(Fluent column) => 'json';
  @override
  String typeJsonb(Fluent column) => 'jsonb';
  @override
  String typeDate(Fluent column) => 'date';
  @override
  String typeDateTime(Fluent column) =>
      'timestamp(${column['precision'] ?? 0}) without time zone';
  @override
  String typeDateTimeTz(Fluent column) =>
      'timestamp(${column['precision'] ?? 0}) with time zone';
  @override
  String typeTime(Fluent column) =>
      'time(${column['precision'] ?? 0}) without time zone';
  @override
  String typeTimeTz(Fluent column) =>
      'time(${column['precision'] ?? 0}) with time zone';
  @override
  String typeTimestamp(Fluent column) =>
      'timestamp(${column['precision'] ?? 0}) without time zone${column['useCurrent'] == true ? ' default CURRENT_TIMESTAMP' : ''}'; // Adicionado default
  @override
  String typeTimestampTz(Fluent column) =>
      'timestamp(${column['precision'] ?? 0}) with time zone${column['useCurrent'] == true ? ' default CURRENT_TIMESTAMP' : ''}'; // Adicionado default
  @override
  String typeYear(Fluent column) {
    print("Warning: PostgreSQL does not have a YEAR type. Using INTEGER.");
    return 'integer';
  }

  @override
  String typeBinary(Fluent column) => 'bytea';
  @override
  String typeUuid(Fluent column) => 'uuid';
  @override
  String typeIpAddress(Fluent column) => 'inet';
  @override
  String typeMacAddress(Fluent column) => 'macaddr';
  @override
  String typeGeometry(Fluent column) => 'geometry${_getSridSql(column)}';
  @override
  String typePoint(Fluent column) =>
      'geometry(Point${_getSridSql(column, includeComma: true)})';
  @override
  String typeLineString(Fluent column) =>
      'geometry(LineString${_getSridSql(column, includeComma: true)})';
  @override
  String typePolygon(Fluent column) =>
      'geometry(Polygon${_getSridSql(column, includeComma: true)})';
  @override
  String typeGeometryCollection(Fluent column) =>
      'geometry(GeometryCollection${_getSridSql(column, includeComma: true)})';
  @override
  String typeMultiPoint(Fluent column) =>
      'geometry(MultiPoint${_getSridSql(column, includeComma: true)})';
  @override
  String typeMultiLineString(Fluent column) =>
      'geometry(MultiLineString${_getSridSql(column, includeComma: true)})';
  @override
  String typeMultiPolygon(Fluent column) =>
      'geometry(MultiPolygon${_getSridSql(column, includeComma: true)})';
  String _getSridSql(Fluent column, {bool includeComma = false}) {
    if (column['srid'] != null && column['srid'] is int) {
      return '${includeComma ? ', ' : ''}${column['srid']}';
    }
    return '';
  }

  // --- Implementações de Modificadores para PostgreSQL ---

  /// Formata o valor padrão para PostgreSQL.
  @override
  @protected
  String getDefaultValue(dynamic value) {
    if (value is QueryExpression) return value.getValue().toString();
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    if (value == null) return 'NULL';
    if (value is String) return "'${value.replaceAll("'", "''")}'";
    return value.toString();
  }

  /// Modificador para UNSIGNED (não suportado no PG).
  @override
  @protected
  String? modifyUnsigned(Blueprint blueprint, Fluent column) {
    print("Warning: PostgreSQL does not support UNSIGNED columns.");
    return null;
  }

  /// Modificador para AUTO_INCREMENT/SERIAL. (Não aplicável como modificador)
  @override
  @protected
  String? modifyIncrementing(Blueprint blueprint, Fluent column) {
    return null; // Tratado pelo tipo serial
  }

  /// Modificador para COMMENT (requer comando separado no PG).
  @override
  @protected
  String? modifyComment(Blueprint blueprint, Fluent column) {
    if (column['comment'] != null) {
      // Não retorna SQL inline, mas a gramática poderia opcionalmente
      // gerar o comando COMMENT ON COLUMN aqui se Blueprint.toSql o coletasse.
      print(
          "Info: Column comment for '${column['name']}' needs separate 'COMMENT ON COLUMN ...' statement.");
    }
    return null;
  }

  /// Modificador para FIRST (não suportado no PG).
  @override
  @protected
  String? modifyFirst(Blueprint blueprint, Fluent column) {
    print("Warning: PostgreSQL does not support FIRST column modifier.");
    return null;
  }

  /// Modificador para AFTER (não suportado no PG).
  @override
  @protected
  String? modifyAfter(Blueprint blueprint, Fluent column) {
    print("Warning: PostgreSQL does not support AFTER column modifier.");
    return null;
  }

  /// Modificador para STORED AS (Generated Columns).
  @override
  @protected
  String? modifyStoredAs(Blueprint blueprint, Fluent column) {
    if (column['storedAs'] != null) {
      final expression = _resolveExpression(column['storedAs']);
      return ' generated always as ($expression) stored';
    }
    return null;
  }

  /// Modificador para VIRTUAL AS (Generated Columns).
  @override
  @protected
  String? modifyVirtualAs(Blueprint blueprint, Fluent column) {
    if (column['virtualAs'] != null) {
      print(
          "Warning: PostgreSQL does not support VIRTUAL generated columns. Using STORED.");
      final expression = _resolveExpression(column['virtualAs']);
      return ' generated always as ($expression) stored';
    }
    return null;
  }

  /// Modificador para CHARSET (não aplicável a nível de coluna no PG).
  @override
  @protected
  String? modifyCharset(Blueprint blueprint, Fluent column) {
    print("Warning: PostgreSQL does not support CHARSET column modifier.");
    return null;
  }

  /// Modificador para COLLATE.
  @override
  @protected
  String? modifyCollate(Blueprint blueprint, Fluent column) {
    if (column['collation'] != null) {
      // Usa wrapValue (aspas duplas) para o nome da collation
      return ' collate ${wrapValue(column['collation'] as String)}';
    }
    return null;
  }

  /// Modificador para SRID (GIS). (Tratado no tipo)
  @override
  @protected
  String? modifySrid(Blueprint blueprint, Fluent column) {
    if (column['srid'] != null) {
      print(
          "Info: SRID for column '${column['name']}' is handled within the geometry type definition in PostgreSQL.");
    }
    return null;
  }

  /// Resolve expressão para colunas geradas.
  @protected
  String _resolveExpression(dynamic expression) {
    return expression is QueryExpression
        ? expression.getValue().toString()
        : expression.toString();
  }

  // --- Overrides para Wrapping ---

  /// Envolve um valor simples em identificadores (aspas duplas para PG).
  @override
  String wrapValue(String value) {
    if (value == '*') return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
