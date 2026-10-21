import 'package:eloquent/eloquent.dart';

/// Interface abstrata para introspecção de schema de banco de dados.
/// Inspirado em Doctrine\DBAL\Schema\AbstractSchemaManager.
abstract class AbstractSchemaManager {
  final ConnectionInterface connection;
  final SchemaGrammar grammar; // Gramática pode ser útil para quoting

  AbstractSchemaManager(this.connection, this.grammar);

  // --- Métodos de Tabela (existentes) ---

  /// Lista os nomes das tabelas no schema/banco de dados padrão.
  Future<List<String>> listTableNames();

  /// Lista as colunas de uma tabela específica.
  /// Retorna um Map onde a chave é o nome canônico da coluna.
  Future<Map<String, Column>> listTableColumns(String tableName);

  /// Lista os índices de uma tabela específica.
  /// Retorna um Map onde a chave é o nome canônico do índice.
  Future<Map<String, Index>> listTableIndexes(String tableName);

  /// Lista as chaves estrangeiras de uma tabela específica.
  /// Retorna um Map onde a chave é o nome canônico da FK.
  Future<Map<String, ForeignKeyConstraint>> listTableForeignKeys(
      String tableName);

  /// Obtém todos os detalhes de uma tabela (colunas, índices, FKs, opções).
  Future<Table> listTableDetails(String tableName) async {
    final name = tableName; // Pode precisar normalizar ou obter do banco
    final columns = await listTableColumns(tableName);
    final indexes = await listTableIndexes(tableName);
    final foreignKeys = await listTableForeignKeys(tableName);
    // unique constraints geralmente são tratados como indexes únicos ou FKs
    final options = await fetchTableOptions(tableName); // Método auxiliar

    return Table(name,
        columns: columns.values.toList(),
        indexes: indexes.values.toList(),
        foreignKeys: foreignKeys.values.toList(),
        options: options);
  }

  /// The name of the schema the unqualified tables belong to (PostgreSQL:
  /// the current schema; MySQL: the database).
  Future<String> getSchemaName() async => 'public';

  /// The tables and sequences of [getSchemaName] as a [Schema], e.g. to
  /// compare with the one the application expects
  /// (`Comparator().compareSchemas(actual, expected)`).
  Future<Schema> introspectSchema() async {
    final tables = <Table>[
      for (final name in await listTableNames()) await listTableDetails(name),
    ];
    final sequences = <Sequence>[
      for (final name in await listSequences()) await listSequenceDetails(name),
    ];
    return Schema(
      tables: tables,
      sequences: sequences,
      schemaConfig: SchemaConfig(name: await getSchemaName()),
    );
  }

  /// Método auxiliar para buscar opções da tabela (ex: comment).
  /// Deve ser implementado pela subclasse.
  Future<Map<String, dynamic>> fetchTableOptions(String tableName);

  /// Verifica se uma tabela existe.
  Future<bool> tablesExist(List<String> tableNames) async {
    if (tableNames.isEmpty) return true; // Ou false? Decide a semântica
    try {
      final existingTables = await listTableNames();
      final existingSet = existingTables.map((t) => t.toLowerCase()).toSet();
      return tableNames.every((t) => existingSet.contains(t.toLowerCase()));
    } catch (_) {
      return false;
    }
  }

  // --- Métodos de View (NOVOS) ---

  /// Lista os nomes das views no schema/banco de dados padrão.
  /// A subclasse deve implementar a query SQL específica.
  Future<List<String>> listViews();

  /// Obtém os detalhes de uma view específica (nome e SQL).
  /// A subclasse deve implementar a query SQL específica e chamar
  /// `parsePortableViewDefinition`.
  Future<View> listViewDetails(String viewName);

  // --- Métodos de Sequence (NOVOS) ---

  /// Lista os nomes das sequences no schema/banco de dados padrão.
  /// A subclasse deve implementar a query SQL específica.
  Future<List<String>> listSequences();

  /// Obtém os detalhes de uma sequence específica (nome, incremento, valor inicial).
  /// A subclasse deve implementar a query SQL específica e chamar
  /// `parsePortableSequenceDefinition`.
  Future<Sequence> listSequenceDetails(String sequenceName);

  // --- Métodos auxiliares para parsear resultados do DB (existentes e NOVOS) ---

  /// Converte uma linha de resultado do banco para um Column.
  Column parsePortableTableColumnDefinition(Map<String, dynamic> tableColumn);

  /// Converte uma linha de resultado do banco para um Index.
  /// Nota: O Doctrine agrupa resultados por índice antes de chamar este método.
  Index parsePortableTableIndexDefinition(Map<String, dynamic> tableIndex);

  /// Converte uma linha de resultado do banco para um ForeignKeyConstraint.
  /// Nota: O Doctrine agrupa resultados por FK antes de chamar este método.
  ForeignKeyConstraint parsePortableTableForeignKeyDefinition(
      Map<String, dynamic> tableForeignKey);

  /// Converte dados brutos do banco para um objeto View.
  /// A subclasse deve implementar a lógica para extrair nome e SQL
  /// dos dados retornados pela sua query em `listViewDetails`.
  View parsePortableViewDefinition(Map<String, dynamic> viewData);

  /// Converte dados brutos do banco para um objeto Sequence.
  /// A subclasse deve implementar a lógica para extrair nome, incremento, etc.
  /// dos dados retornados pela sua query em `listSequenceDetails`.
  Sequence parsePortableSequenceDefinition(Map<String, dynamic> sequenceData);
}
