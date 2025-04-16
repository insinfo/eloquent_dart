import 'package:eloquent/eloquent.dart';
import 'abstract_schema_manager.dart'; // <-- Certifique-se de que este caminho esteja correto

import 'column.dart';
import 'index.dart';
import 'foreign_key_constraint.dart';
import 'view.dart';
import 'sequence.dart'; // <-- Importar Sequence
import 'schema_config.dart';
import 'package:meta/meta.dart';
import 'dart:async';

/// Implementação do SchemaManager para PostgreSQL.
/// Inspirado em Doctrine\DBAL\Schema\PostgreSQLSchemaManager.
class PostgreSQLSchemaManager extends AbstractSchemaManager {
  /// Cache para o nome do schema atual para evitar múltiplas queries.
  String? _currentSchema;

  PostgreSQLSchemaManager(ConnectionInterface connection)
      // Passa a gramática específica do Postgres para a classe base
      : super(connection, SchemaPostgresGrammar());

  /// Retorna o nome do schema atual conectado.
  /// Tenta buscar do banco ou usa 'public' como fallback.
  @protected
  Future<String> getCurrentSchema() async {
    // Retorna do cache se já buscado
    if (_currentSchema != null) {
      return _currentSchema!;
    }
    try {
      // Busca o schema atual do banco
      final result = await connection.selectOne('SELECT current_schema()');
      _currentSchema = result?['current_schema'] as String? ?? 'public';
    } catch (e) {
      print(
          "Warning: Could not determine current schema, defaulting to 'public'. Error: $e");
      _currentSchema = 'public'; // Fallback
    }
    return _currentSchema!;
  }

  /// Cria uma configuração de schema, definindo o nome padrão.
  /// (Similar ao PHP, mas pode não ser estritamente necessário em Dart)

  Future<SchemaConfig> createSchemaConfig() async {
    final config = SchemaConfig(); // Assume construtor padrão
    final currentSchemaName = await getCurrentSchema();
    return config
      ..setName(currentSchemaName); // Assume que SchemaConfig tem setName
  }

  /// Verifica se um identificador está entre aspas (", `, []).
  bool isIdentifierQuoted(String identifier) {
    if (identifier.length < 2)
      return false; // Precisa de pelo menos 2 caracteres para as aspas
    final firstChar = identifier[0];
    final lastChar = identifier[identifier.length - 1];
    return (firstChar == '"' && lastChar == '"') ||
        (firstChar == '`' && lastChar == '`') ||
        (firstChar == '[' && lastChar == ']');
  }

  /// Remove as aspas delimitadoras (", `, []) de um identificador.
  /// Se não estiver cotado, retorna o identificador original.
  String trimQuotes(String identifier) {
    // <-- MÉTODO ADICIONADO/CORRIGIDO
    if (isIdentifierQuoted(identifier)) {
      // Remove o primeiro e o último caractere
      return identifier.substring(1, identifier.length - 1);
    }
    return identifier; // Retorna original se não estava cotado
  }

  /// Lista os nomes dos schemas (namespaces) no banco de dados.

  Future<List<String>> listSchemaNames() async {
    const sql = '''
      SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name NOT LIKE 'pg\\_%'
      AND schema_name != 'information_schema'
      ORDER BY schema_name
    ''';
    final results = await connection.select(sql);
    return results.map((row) => row['schema_name'] as String).toList();
  }

  /// Lista os nomes das tabelas no schema/banco de dados padrão ou especificado.
  @override
  Future<List<String>> listTableNames() async {
    final currentSchema = await getCurrentSchema();
    // Usa a query da gramática base que já inclui schema
    final sql = grammar.compileTableExists();
    //final dbName = connection.getDatabaseName();
    // Os parâmetros agora são [table_schema, table_name], adaptamos para listar todas as tabelas do schema
    final results = await connection.select(
        sql
            .replaceFirst('select *', 'select table_name') // Pega só o nome
            .replaceFirst(
                'table_name = ?', '1 = 1'), // Remove filtro por nome específico
        [currentSchema] // Filtra apenas pelo schema atual
        );
    return results.map((row) => row['table_name'] as String).toList();
  }

  /// Lista as colunas de uma tabela específica.
  @override
  Future<Map<String, Column>> listTableColumns(String tableName) async {
    final schemaAndTable = await _parseSchemaAndTable(tableName);
    final currentSchema = schemaAndTable[0];
    final cleanTableName = schemaAndTable[1];

    final Map<String, Column> columns = {};
    // Query refinada para PostgreSQL, buscando mais detalhes
    final sql = '''
        SELECT
            a.attname AS field,
            a.attnum,
            format_type(a.atttypid, a.atttypmod) AS complete_type,
            t.typname AS type,
            -- a.attlen AS length, -- attlen nem sempre é útil
            a.atttypmod AS typemod,
            a.attnotnull AS isnotnull,
            (SELECT pg_get_expr(ad.adbin, ad.adrelid)
             FROM pg_attrdef ad
             WHERE ad.adrelid = a.attrelid AND ad.adnum = a.attnum AND ad.adinhcount = 0
            ) AS default,
            (SELECT col_description(a.attrelid, a.attnum)) AS comment,
            a.attidentity, -- 'd' for DEFAULT (serial), 'a' for ALWAYS
            (SELECT tc.collcollate FROM pg_catalog.pg_collation tc WHERE tc.oid = a.attcollation) AS collation,
            (SELECT t1.typname FROM pg_catalog.pg_type t1 WHERE t1.oid = t.typbasetype) AS domain_type,
            (SELECT format_type(t2.typbasetype, t2.typtypmod) FROM
              pg_catalog.pg_type t2 WHERE t2.typtype = 'd' AND t2.oid = a.atttypid) AS domain_complete_type
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_type t ON t.oid = a.atttypid
        WHERE c.relname = ? AND n.nspname = ? AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum;
     ''';

    final results =
        await connection.select(sql, [cleanTableName, currentSchema]);

    for (final row in results) {
      final column = parsePortableTableColumnDefinition(row);
      columns[column.getCanonicalName()] = column;
    }
    return columns;
  }

  /// Lista os índices de uma tabela específica.
  @override
  Future<Map<String, Index>> listTableIndexes(String tableName) async {
    final schemaAndTable = await _parseSchemaAndTable(tableName);
    final currentSchema = schemaAndTable[0];
    final cleanTableName = schemaAndTable[1];

    final Map<String, Index> indexes = {};

    // Query para obter informações básicas do índice
    const indexSql = '''
            SELECT
                ic.relname AS indexname,
                i.indisprimary AS primary,
                i.indisunique AS unique,
                i.indkey AS columns_ordinals,
                i.indrelid AS table_oid,
                pg_get_indexdef(i.indexrelid) AS indexdef, -- Definição completa
                 pg_get_expr(i.indpred, i.indrelid) AS "where" -- Condição WHERE para índice parcial
            FROM pg_index i
            JOIN pg_class AS ic ON ic.oid = i.indexrelid
            JOIN pg_class AS tc ON tc.oid = i.indrelid
            JOIN pg_namespace AS tn ON tn.oid = tc.relnamespace
            WHERE tc.relname = ? AND tn.nspname = ?;
       ''';

    final indexResults =
        await connection.select(indexSql, [cleanTableName, currentSchema]);

    if (indexResults.isEmpty) {
      return {};
    }

    // Mapear OID da tabela para buscar nomes de coluna eficientemente
    final tableOid = indexResults
        .first['table_oid']; // Assume mesmo OID para todos os índices da tabela

    // Query para buscar todos os nomes de coluna da tabela de uma vez
    const columnSql = '''
          SELECT attnum, attname
          FROM pg_attribute
          WHERE attrelid = ? AND attnum > 0 AND NOT attisdropped;
      ''';
    final columnResults = await connection.select(columnSql, [tableOid]);
    // Criar mapa de ordinal para nome de coluna
    final columnOrdinalMap = {
      for (var row in columnResults)
        (row['attnum'] as int): (row['attname'] as String)
    };

    // Processar cada índice
    for (final indexRow in indexResults) {
      final String indexName = indexRow['indexname'];
      final bool isPrimary = indexRow['primary'];
      final bool isUnique = indexRow['unique'];
      final String ordinalString = indexRow['columns_ordinals'];
      final String? whereCondition = indexRow['where'];
      final String indexDef = indexRow['indexdef'];

      // Mapear ordinais para nomes de coluna
      final List<String> columnNames = ordinalString
          .split(' ')
          .map((s) => int.tryParse(s))
          .where((ordinal) =>
              ordinal != null && columnOrdinalMap.containsKey(ordinal))
          .map((ordinal) => columnOrdinalMap[ordinal]!)
          .toList();

      if (columnNames.isEmpty && ordinalString != '0') {
        print(
            "Warning: Could not map ordinals '$ordinalString' to column names for index '$indexName'. Skipping index.");
        continue;
      }

      // Extrair flags e options (simplificado, pode precisar de mais parsing de indexdef)
      final List<String> flags = [];
      final Map<String, dynamic> options = {};
      if (whereCondition != null && whereCondition.isNotEmpty) {
        options['where'] = whereCondition;
      }
      // Exemplo de extração de flag (simplista)
      if (indexDef.contains('DESC')) flags.add('DESC');
      if (indexDef.contains('NULLS FIRST')) flags.add('NULLS FIRST');
      if (indexDef.contains('NULLS LAST')) flags.add('NULLS LAST');
      // TODO: Extrair tipo de índice (USING btree/hash/gist/gin) etc.

      final index = Index(
        name: indexName,
        columns: columnNames,
        isPrimary: isPrimary,
        isUnique: isUnique,
        flags: flags,
        options: options,
      );
      indexes[index.getCanonicalName()] = index;
    }
    return indexes;
  }

  /// Lista as chaves estrangeiras de uma tabela específica.
  @override
  Future<Map<String, ForeignKeyConstraint>> listTableForeignKeys(
      String tableName) async {
    final schemaAndTable = await _parseSchemaAndTable(tableName);
    final currentSchema = schemaAndTable[0];
    final cleanTableName = schemaAndTable[1];

    final Map<String, ForeignKeyConstraint> foreignKeys = {};
    const sql = '''
           SELECT
               conname AS name,
               pg_get_constraintdef(oid, true) AS definition
           FROM pg_constraint
           WHERE conrelid = (SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relname = ? AND n.nspname = ?)
           AND contype = 'f'
           ORDER BY conname;
        ''';
    final results =
        await connection.select(sql, [cleanTableName, currentSchema]);
    for (final row in results) {
      try {
        final fk = parsePortableTableForeignKeyDefinition(row);
        foreignKeys[fk.getCanonicalName()] = fk;
      } catch (e) {
        print(
            "Warning: Could not parse foreign key definition '${row['definition']}'. Error: $e");
      }
    }
    return foreignKeys;
  }

  /// Busca opções da tabela (atualmente só comentário).
  @override
  Future<Map<String, dynamic>> fetchTableOptions(String tableName) async {
    final schemaAndTable = await _parseSchemaAndTable(tableName);
    final currentSchema = schemaAndTable[0];
    final cleanTableName = schemaAndTable[1];

    const sql = '''
          SELECT obj_description(c.oid, 'pg_class') AS comment
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relname = ? AND n.nspname = ? AND c.relkind IN ('r', 'p'); -- 'r' for table, 'p' for partitioned table
     ''';
    final result =
        await connection.selectOne(sql, [cleanTableName, currentSchema]);
    final options = <String, dynamic>{};
    if (result != null && result['comment'] != null) {
      options['comment'] = result['comment'];
    }
    // TODO: Buscar outras opções como UNLOGGED?
    return options;
  }

  // --- NOVOS MÉTODOS PARA VIEWS E SEQUENCES ---

  @override
  Future<List<String>> listViews() async {
    final currentSchema = await getCurrentSchema();
    const sql = '''
      SELECT viewname AS view_name
      FROM pg_catalog.pg_views
      WHERE schemaname = ?
      ORDER BY viewname
    ''';
    // Usando pg_catalog em vez de information_schema para potentially maior performance/detalhe
    // Se preferir information_schema:
    // const sql = '''
    //   SELECT table_name
    //   FROM information_schema.views
    //   WHERE table_schema = ?
    //   ORDER BY table_name
    // ''';
    final results = await connection.select(sql, [currentSchema]);
    return results.map((row) => row['view_name'] as String).toList();
  }

  @override
  Future<View> listViewDetails(String viewName) async {
    final schemaAndView = await _parseSchemaAndTable(viewName);
    final currentSchema = schemaAndView[0];
    final cleanViewName = schemaAndView[1];

    const sql = '''
      SELECT definition AS view_definition
      FROM pg_catalog.pg_views
      WHERE schemaname = ? AND viewname = ?
    ''';
    // Usando pg_catalog
    // Se preferir information_schema:
    // const sql = '''
    //   SELECT view_definition
    //   FROM information_schema.views
    //   WHERE table_schema = ? AND table_name = ?
    // ''';
    final results = await connection.select(sql, [currentSchema, cleanViewName]);

    if (results.isEmpty) {
      throw Exception('View "$viewName" not found in schema "$currentSchema".');
    }

    final viewData = Map<String, dynamic>.from(results.first);
    // Adiciona o nome original (potencialmente qualificado) para o parser
    viewData['view_name'] = viewName;

    return parsePortableViewDefinition(viewData);
  }

  @override
  Future<List<String>> listSequences() async {
    final currentSchema = await getCurrentSchema();
    const sql = '''
      SELECT sequence_name
      FROM information_schema.sequences
      WHERE sequence_schema = ?
      ORDER BY sequence_name
    ''';
    final results = await connection.select(sql, [currentSchema]);
    return results.map((row) => row['sequence_name'] as String).toList();
  }

  @override
  Future<Sequence> listSequenceDetails(String sequenceName) async {
    final schemaAndSequence = await _parseSchemaAndTable(sequenceName);
    final currentSchema = schemaAndSequence[0];
    final cleanSequenceName = schemaAndSequence[1];

    // information_schema.sequences é mais padrão
    const sql = '''
      SELECT start_value, increment -- , minimum_value, maximum_value, cycle_option
      FROM information_schema.sequences
      WHERE sequence_schema = ? AND sequence_name = ?
    ''';
    final results = await connection.select(sql, [currentSchema, cleanSequenceName]);

    if (results.isEmpty) {
      throw Exception('Sequence "$sequenceName" not found in schema "$currentSchema".');
    }

    final sequenceData = Map<String, dynamic>.from(results.first);
    // Adiciona o nome original (potencialmente qualificado) para o parser
    sequenceData['sequence_name'] = sequenceName;

    return parsePortableSequenceDefinition(sequenceData);
  }

  // --- Implementações de Parse (Métodos protegidos) ---

  @override
  @protected
  Column parsePortableTableColumnDefinition(Map<String, dynamic> tableColumn) {
    // (Implementação mantida como estava)
    final name = tableColumn['field'] as String;
    final pgType = tableColumn['type'] as String;
    final completeType = tableColumn['complete_type'] as String;
    final defaultValue = tableColumn['default'] as String?;
    final isNullable = !(tableColumn['isnotnull'] as bool? ?? true);
    final comment = tableColumn['comment'] as String?;
    final pgIdentity =
        tableColumn['attidentity'] as String?; // 'd' ou 'a' ou ''
    final collation = tableColumn['collation'] as String?;
    final domainType = tableColumn['domain_type'] as String?;
    final domainCompleteType = tableColumn['domain_complete_type'] as String?;

    final finalPgType = (domainType != null &&
            domainType.isNotEmpty &&
            !_platformHasTypeMapping(pgType))
        ? domainType
        : pgType;
    final finalCompleteType = (domainType != null &&
            domainType.isNotEmpty &&
            !_platformHasTypeMapping(pgType))
        ? domainCompleteType ?? completeType
        : completeType;

    String dartType = _mapPgTypeToDartType(finalPgType, finalCompleteType);
    bool autoIncrement = pgIdentity == 'd' || pgIdentity == 'a';

    int? length;
    int? precision;
    int? scale;
    bool fixed = false;

    if (dartType == 'string' || dartType == 'char') {
      final match = RegExp(r'\((?<len>\d+)\)').firstMatch(finalCompleteType);
      length = int.tryParse(match?.namedGroup('len') ?? '');
      if (pgType == 'bpchar' || dartType == 'char') fixed = true;
    } else if (['decimal', 'numeric', 'money'].contains(dartType)) {
      final match =
          RegExp(r'\((?<prec>\d+)(?:,(?<scale>\d+))?\)')
              .firstMatch(finalCompleteType);
      precision = int.tryParse(match?.namedGroup('prec') ?? '');
      scale = int.tryParse(match?.namedGroup('scale') ?? '');
    } else if (['timestamp', 'timestamptz', 'time', 'timetz']
        .contains(dartType)) {
      final match = RegExp(r'\((?<prec>\d+)\)').firstMatch(finalCompleteType);
      precision = int.tryParse(match?.namedGroup('prec') ?? '');
    }

    dynamic finalDefault = _parsePgDefaultValue(defaultValue, dartType);

    return Column(name, dartType, options: {
      'length': length,
      'precision': precision,
      'scale': scale,
      'nullable': isNullable,
      'default': finalDefault,
      'comment': comment,
      'autoIncrement': autoIncrement,
      'fixed': fixed,
      'collation': collation,
    });
  }

  bool _platformHasTypeMapping(String pgTypeName) {
     // (Implementação mantida como estava)
    return _mapPgTypeToDartType(pgTypeName, '') != 'string';
  }

  String _mapPgTypeToDartType(String pgType, String completeType) {
    // (Implementação mantida como estava)
     switch (pgType.toLowerCase()) {
      case 'int2': return 'smallinteger';
      case 'int4': return 'integer';
      case 'int8': return 'biginteger';
      case 'serial2': return 'smallinteger';
      case 'serial4': return 'integer';
      case 'serial8': return 'biginteger';
      case 'bpchar': return 'char';
      case 'varchar': return 'string';
      case 'text': return 'text';
      case 'numeric': return 'decimal';
      case 'float4': return 'float';
      case 'float8': return 'double';
      case 'bool': return 'boolean';
      case 'date': return 'date';
      case 'time': return 'time';
      case 'timetz': return 'timetz';
      case 'timestamp': return 'timestamp';
      case 'timestamptz': return 'timestamptz';
      case 'bytea': return 'binary';
      case 'uuid': return 'uuid';
      case 'json': return 'json';
      case 'jsonb': return 'jsonb';
      case 'inet': return 'ipaddress';
      case 'macaddr': return 'macaddress';
      case '_int2': return 'array';
      case '_int4': return 'array';
      case '_int8': return 'array';
      case '_text': return 'array';
      case '_varchar': return 'array';
      case '_float4': return 'array';
      case '_float8': return 'array';
      default:
        if (pgType.endsWith('_enum')) return 'enum';
        print("Warning: Unmapped PostgreSQL type '$pgType' ($completeType). Falling back to 'string'.");
        return 'string';
    }
  }

  dynamic _parsePgDefaultValue(String? pgDefault, String dartType) {
    // (Implementação mantida como estava)
    if (pgDefault == null) return null;
    pgDefault = pgDefault.replaceAllMapped(
        RegExp(r'^(.+)::[a-zA-Z_"\s]+(\(.+\))?$'), (m) => m.group(1) ?? '');
    if (pgDefault.toLowerCase().startsWith('nextval(')) return null;
    if (pgDefault.startsWith("'") && pgDefault.endsWith("'")) return pgDefault.substring(1, pgDefault.length - 1).replaceAll("''", "'");
    if (dartType == 'boolean') {
      if (pgDefault.toLowerCase() == 'true') return true;
      if (pgDefault.toLowerCase() == 'false') return false;
    }
    if (isNumericType(dartType)) return num.tryParse(pgDefault);
    if (['now()', 'current_timestamp', 'current_date', 'current_time']
        .contains(pgDefault.toLowerCase())) return QueryExpression(pgDefault);
    return pgDefault;
  }

  @override
  @protected
  Index parsePortableTableIndexDefinition(Map<String, dynamic> tableIndex) {
     // (Implementação mantida como estava)
    throw UnimplementedError('parsePortableTableIndexDefinition needs the calling method (listTableIndexes) to provide grouped data with column names.');
  }

  @override
  @protected
  ForeignKeyConstraint parsePortableTableForeignKeyDefinition(
      Map<String, dynamic> tableForeignKey) {
     // (Implementação mantida como estava)
    final name = tableForeignKey['name'] as String;
    final definition = tableForeignKey['definition'] as String;

    final fkMatch = RegExp(r'FOREIGN KEY\s*\((.+)\)\s*REFERENCES\s*"?([^"]+)"?(?:\."?([^"]+)"?)?\s*\((.+)\)', caseSensitive: false).firstMatch(definition);
    if (fkMatch == null) throw FormatException("Could not parse FK definition: $definition");

    final localColumns = fkMatch.group(1)!.split(',').map((s) => trimQuotes(s.trim())).toList();
    final group2 = fkMatch.group(2);
    final group3 = fkMatch.group(3);
    final foreignColumns = fkMatch.group(4)!.split(',').map((s) => trimQuotes(s.trim())).toList();

    String foreignTable;
    String? foreignSchema;
    if (group3 == null) {
      foreignTable = trimQuotes(group2!);
      foreignSchema = null;
    } else {
      foreignSchema = trimQuotes(group2!);
      foreignTable = trimQuotes(group3);
    }
    final fullForeignTable = (foreignSchema != null && foreignSchema.isNotEmpty && foreignSchema != 'public') ? '$foreignSchema.$foreignTable' : foreignTable;

    String? onDelete;
    String? onUpdate;
    final actionRegex = RegExp(r'(CASCADE|SET NULL|SET DEFAULT|RESTRICT|NO ACTION)', caseSensitive: false);
    final onDeleteMatch = RegExp(r'ON DELETE (' + actionRegex.pattern + r')').firstMatch(definition);
    if (onDeleteMatch != null) onDelete = onDeleteMatch.group(1)?.toUpperCase();
    final onUpdateMatch = RegExp(r'ON UPDATE (' + actionRegex.pattern + r')').firstMatch(definition);
    if (onUpdateMatch != null) onUpdate = onUpdateMatch.group(1)?.toUpperCase();

    return ForeignKeyConstraint(
        name: name,
        localColumns: localColumns,
        foreignTableName: fullForeignTable,
        foreignColumns: foreignColumns,
        options: {
          if (onDelete != null) 'ondelete': onDelete,
          if (onUpdate != null) 'onupdate': onUpdate,
        });
  }

  @override
  @protected
  View parsePortableViewDefinition(Map<String, dynamic> viewData) {
    // Extrai o nome (passado de listViewDetails) e a definição SQL
    final name = viewData['view_name'] as String;
    final sql = viewData['view_definition'] as String? ?? '';
    return View(name, sql);
  }

  @override
  @protected
  Sequence parsePortableSequenceDefinition(Map<String, dynamic> sequenceData) {
    // Extrai o nome (passado de listSequenceDetails) e os detalhes
    final name = sequenceData['sequence_name'] as String;
    // Valores do information_schema geralmente são strings, converte para int
    final initialValue = int.tryParse(sequenceData['start_value']?.toString() ?? '1') ?? 1;
    // Mapeia 'increment' do DB para 'cache' na nossa classe Sequence
    final cache = int.tryParse(sequenceData['increment']?.toString() ?? '1') ?? 1;

    // Nota: Nossa classe Sequence atual só armazena initialValue e cache.
    // Se precisar de min/max/cycle, precisaria buscar e adicionar à classe Sequence.
    return Sequence(
      name,
      initialValue: initialValue,
      cache: cache,
    );
  }


  // --- Helpers Internos ---

  /// Parseia um nome de tabela/view/sequence potencialmente qualificado por schema.
  /// Retorna [schema, nome]. Usa o schema atual se não for especificado.
  Future<List<String>> _parseSchemaAndTable(String name) async {
     // (Implementação mantida como estava)
    final currentSchema = await getCurrentSchema();
    if (name.contains('.')) {
      final parts = name.split('.');
      if (parts.length == 2) {
        return [parts[0], parts[1]];
      } else {
        print("Warning: Invalid qualified name '$name'. Using default schema '$currentSchema'.");
        return [currentSchema, name];
      }
    }
    return [currentSchema, name];
  }


  /// Método auxiliar para verificar se um tipo é numérico (baseado nos nomes mapeados).
  bool isNumericType(String dartTypeName) {
     // (Implementação mantida como estava)
    final numericTypes = {
      'integer', 'tinyinteger', 'smallinteger', 'mediuminteger', 'biginteger',
      'decimal', 'float', 'double', 'real', 'numeric', 'money'
    };
    return numericTypes.contains(dartTypeName.toLowerCase());
  }

  // --- Métodos não implementados/relevantes do PHP (mantidos) ---
  // ... (outros métodos não relevantes mantidos como estavam)
}