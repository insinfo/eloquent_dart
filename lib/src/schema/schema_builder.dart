// ignore_for_file: unnecessary_null_comparison

import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';
import 'dart:async';

/// Provides an API for managing the database schema.
/// Mirrors Laravel's Illuminate\Database\Schema\Builder.
class SchemaBuilder {
  /// The database connection instance.
  /// Use ConnectionInterface for better decoupling.
  late Connection connection;

  /// The schema grammar instance, determined by the connection.
  late SchemaGrammar grammar;

  /// An optional callback to resolve Blueprint instances.
  /// Allows for customizing Blueprint creation.
  Function(String table, Function(Blueprint)? callback)? resolver;

  /// Creates a new database Schema manager.
  ///
  /// [connection] The database connection instance.
  SchemaBuilder(Connection connection) {
    setConnection(
        connection); // Use setter to initialize connection and grammar
  }

  /// Determina se a tabela dada existe no schema padrão.
  ///
  /// [tableName] O nome da tabela (sem prefixo).
  Future<bool> hasTable(String tableName) async {
    final String schema = await _getSchemaName();
    final String sql = grammar.compileTableExists();
    // Query information_schema using schema and table name without prefix
    final results = await connection.select(sql, [schema, tableName]);
    return results.isNotEmpty;
  }

  /// Determina se a tabela dada tem a coluna especificada.
  ///
  /// [tableName] O nome da tabela (sem prefixo).
  /// [columnName] O nome da coluna.
  Future<bool> hasColumn(String tableName, String columnName) async {
    final column = columnName.toLowerCase();
    // getColumnListing is now async
    final tableColumns = await getColumnListing(tableName);
    return tableColumns.map((c) => c.toLowerCase()).contains(column);
  }

  /// Determina se a tabela dada tem todas as colunas especificadas.
  ///
  /// [tableName] O nome da tabela (sem prefixo).
  /// [columns] A lista de nomes de coluna.
  Future<bool> hasColumns(String tableName, List<String> columns) async {
    final tableColumns = (await getColumnListing(tableName)) // await async call
        .map((c) => c.toLowerCase())
        .toSet(); // Use Set for efficient lookups

    for (final column in columns) {
      if (!tableColumns.contains(column.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  /// Obtém a listagem de nomes de coluna para a tabela dada no schema padrão.
  ///
  /// [tableName] O nome da tabela (sem prefixo).
  Future<List<String>> getColumnListing(String tableName) async {
    final String schema = await _getSchemaName();
    final String sql = grammar
        .compileColumnExists(tableName); // Grammar expects unprefixed name

    // Query information_schema using schema and table name
    final results = await connection.select(sql, [schema, tableName]);

    if (results.isEmpty) {
      return [];
    }
    // Assumes the query returns maps with 'column_name' key
    return results.map((row) => row['column_name'] as String).toList();
  }

  /// Modifica uma tabela existente no schema.
  ///
  /// [tableName] O nome da tabela.
  /// [callback] Uma função que recebe o Blueprint para definir as alterações.
  Future<void> table(String tableName, Function(Blueprint) callback) async {
    // Passa o callback para createBlueprint e executa
    await build(createBlueprint(tableName, callback));
  }

  /// Cria uma nova tabela no schema.
  ///
  /// [tableName] O nome da tabela.
  /// [callback] Uma função que recebe o Blueprint para definir as colunas e índices.
  Future<void> create(String tableName, Function(Blueprint) callback) async {
    final blueprint = createBlueprint(tableName);
    blueprint.create(); // Marca a intenção de criar
    callback(blueprint); // Permite ao usuário definir a estrutura
    await build(blueprint); // Executa o blueprint
  }

  /// Dropa (remove) uma tabela do schema.
  ///
  /// [tableName] O nome da tabela.
  Future<void> drop(String tableName) async {
    final blueprint = createBlueprint(tableName);
    blueprint.drop();
    await build(blueprint);
  }

  /// Dropa (remove) uma tabela do schema se ela existir.
  ///
  /// [tableName] O nome da tabela.
  Future<void> dropIfExists(String tableName) async {
    final blueprint = createBlueprint(tableName);
    blueprint.dropIfExists();
    await build(blueprint);
  }

  /// Renomeia uma tabela no schema.
  ///
  /// [from] O nome atual da tabela.
  /// [to] O novo nome da tabela.
  Future<void> rename(String from, String to) async {
    final blueprint = createBlueprint(from);
    blueprint.rename(to);
    await build(blueprint);
  }

  /// Habilita restrições de chave estrangeira (se suportado pela gramática).
  /// Retorna `true` se o comando foi executado com sucesso (ou não era necessário),
  /// `false` se não suportado ou falhou.
  Future<bool> enableForeignKeyConstraints() async {
    // Pede o SQL à gramática
    final List<String> sqlCommands =
        grammar.compileEnableForeignKeyConstraints();
    if (sqlCommands.isEmpty) {
      print(
          "Warning: enableForeignKeyConstraints() is not supported by the current database grammar (${grammar.runtimeType}).");
      return false; // Não suportado pela gramática
    }
    try {
      for (final sql in sqlCommands) {
        // Usa execute pois geralmente não retorna linhas
        await connection.execute(sql);
      }
      return true;
    } catch (e) {
      print("Error enabling foreign key constraints: $e");
      return false; // Falha na execução
    }
  }

  /// Desabilita restrições de chave estrangeira (se suportado pela gramática).
  /// Retorna `true` se o comando foi executado com sucesso (ou não era necessário),
  /// `false` se não suportado ou falhou.
  Future<bool> disableForeignKeyConstraints() async {
    final List<String> sqlCommands =
        grammar.compileDisableForeignKeyConstraints();
    if (sqlCommands.isEmpty) {
      print(
          "Warning: disableForeignKeyConstraints() is not supported by the current database grammar (${grammar.runtimeType}).");
      return false;
    }
    try {
      for (final sql in sqlCommands) {
        await connection.execute(sql);
      }
      return true;
    } catch (e) {
      print("Error disabling foreign key constraints: $e");
      return false;
    }
  }

  /// Executa o blueprint para construir / modificar a tabela.
  /// Método protegido para uso interno.
  @protected
  Future<void> build(Blueprint blueprint) async {
    // Delega a execução para o método build assíncrono do Blueprint
    await blueprint.build(connection, grammar);
  }

  /// Cria uma nova instância de Blueprint.
  /// Utiliza o resolvedor customizado se disponível.
  @protected
  Blueprint createBlueprint(String table, [Function(Blueprint)? callback]) {
    if (resolver != null) {
      // O resolver deve retornar um Blueprint
      // A assinatura do resolver foi ajustada para Function(String, Function?)?
      // Garantimos que o callback passado seja do tipo correto.
      return resolver!(table, callback) as Blueprint;
    }
    return Blueprint(table, callback);
  }

  /// Obtém a instância da conexão com o banco de dados.
  ConnectionInterface getConnection() {
    return connection;
  }

  /// Define a instância da conexão com o banco de dados e atualiza a gramática.
  SchemaBuilder setConnection(Connection connectionP) {
    connection = connectionP;
    // Tenta obter a gramática da conexão. Requer que a implementação de
    // ConnectionInterface (ou a classe concreta Connection) tenha o método.

    grammar = connection.getSchemaGrammar();

    return this;
  }

  /// Define o callback resolvedor de Blueprint customizado.
  void blueprintResolver(
      Function(String table, Function(Blueprint)? callback)? resolverCallback) {
    resolver = resolverCallback;
  }

  /// Helper interno para obter o nome do schema/database da conexão.
  /// Tenta obter da configuração ou do nome do banco de dados da conexão.
  Future<String> _getSchemaName() async {
    String? schema;
    // Tenta obter 'schema' ou 'database' da configuração da conexão (se for a classe concreta Connection)

    final connImpl = connection;
    // Assumindo que getConfig existe e pode retornar null
    schema = connImpl.getConfig('schema') ?? connImpl.getConfig('database');

    // Se não encontrou na config, tenta buscar o nome do banco de dados da conexão
    // Assumindo que getDatabaseName existe na ConnectionInterface ou Connection
    schema ??= connection.getDatabaseName();

    if (schema == null || schema.isEmpty) {
      print(
          "Warning: Could not determine schema/database name. Falling back to 'public' or potential errors.");
      // Fallback comum para PG, pode não ser ideal para outros bancos.
      // Considerar lançar um erro se o schema for essencial e não puder ser determinado.
      return 'public';
    }
    return schema;
  }
}
