import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/schema/identifier.dart';
import 'abstract_asset.dart';

/// Representa uma constraint UNIQUE de banco de dados em memória.
/// Mais alinhado com Doctrine\DBAL\Schema\UniqueConstraint.
class UniqueConstraint extends AbstractAsset {
  /// Colunas que compõem a constraint.
  /// Mapeia nome original da coluna para um objeto Identifier.
  /// Usar LinkedHashMap para manter ordem de inserção.
  /// Tornando mutável internamente para permitir atualização em `Table._updateColumnInIndexesAndFKs`.
  /// Getters retornarão cópias imutáveis.
  Map<String, Identifier> _columns = LinkedHashMap();

  /// Flags específicos da plataforma (ex: 'CLUSTERED').
  /// Mapeia nome da flag (lowercase) para true.
  /// Tornando mutável internamente.
  Map<String, bool> _flags = {};

  /// Opções específicas da plataforma (ex: 'where' para índice parcial UNIQUE).
  final Map<String, dynamic> _options;

  /// Construtor principal.
  UniqueConstraint({
    required String name,
    required List<String> columns,
    List<String> flags = const [],
    Map<String, dynamic> options = const {},
  }) : _options =
            Map.unmodifiable(options) // Torna opções imutáveis na atribuição
  {
    // Usa setName da classe base para inicializar _name e _quoted
    setName(name); // <-- Usa setName

    // Adiciona colunas e flags usando os métodos internos
    for (final column in columns) {
      addColumn(column); // Chama o método interno para adicionar
    }
    for (final flag in flags) {
      addFlag(flag); // Chama o método interno para adicionar
    }

    if (this._columns.isEmpty) {
      throw ArgumentError(
          'Unique constraint "$name" must span at least one column.');
    }
  }

  /// Construtor de fábrica a partir de um comando Fluent do Blueprint.
  factory UniqueConstraint.fromFluent(
      Fluent command, String defaultName, String table) {
    // O comando 'unique' no blueprint usa 'index' para o nome da constraint
    final name = command['index'] as String? ?? defaultName;
    final columns = List<String>.from(
        (command['columns'] as List<dynamic>? ?? []).map((c) => c.toString()));
    final flags = List<String>.from(
        (command['flags'] as List<dynamic>? ?? []).map((f) => f.toString()));
    final options = Map<String, dynamic>.from(command['options'] as Map? ?? {});

    // Cria a instância usando o construtor principal que chamará addColumn/addFlag
    return UniqueConstraint(
      name: name,
      columns: columns,
      flags: flags,
      options: options,
    );
  }

  /// Adiciona uma coluna à constraint internamente.
  void addColumn(String columnName) {
    // A chave do mapa é o nome original para preservar o case se necessário,
    // mas a comparação geralmente deve ser case-insensitive.
    // O valor é um Identifier para encapsular a lógica de quoting.
    if (!_columns.containsKey(columnName)) {
      // Evita duplicatas exatas
      _columns[columnName] = Identifier(columnName);
    }
  }

  /// Retorna a lista de nomes de coluna originais (preserva case).
  /// Retorna cópia imutável.
  List<String> getColumns() {
    return List.unmodifiable(_columns.keys);
  }

  /// Retorna a lista de nomes de coluna com aspas aplicadas pela gramática.
  List<String> getQuotedColumns(SchemaGrammar grammar) {
    return List.unmodifiable(
        _columns.values.map((identifier) => identifier.getQuotedName(grammar)));
  }

  /// Retorna a lista de nomes de coluna sem aspas e em minúsculas para comparação.
  List<String> getUnquotedColumns() {
    return List.unmodifiable(
        _columns.keys.map((colName) => trimQuotes(colName).toLowerCase()));
  }

  /// Adiciona uma flag (case-insensitive).
  UniqueConstraint addFlag(String flag) {
    _flags[flag.toLowerCase()] = true;
    return this;
  }

  /// Verifica se uma flag específica está presente (case-insensitive).
  bool hasFlag(String flag) {
    return _flags.containsKey(flag.toLowerCase());
  }

  /// Remove uma flag (case-insensitive).
  void removeFlag(String flag) {
    _flags.remove(flag.toLowerCase());
  }

  /// Retorna a lista de flags (em minúsculas).
  /// Retorna cópia imutável.
  List<String> getFlags() {
    return List.unmodifiable(_flags.keys);
  }

  /// Retorna o mapa de opções (imutável).
  Map<String, dynamic> getOptions() {
    return _options; // Já é imutável
  }

  /// Verifica se uma opção específica está presente (case-insensitive nas chaves).
  bool hasOption(String name) {
    return _options.keys.any((key) => key.toLowerCase() == name.toLowerCase());
  }

  /// Obtém o valor de uma opção específica (case-insensitive na chave).
  dynamic getOption(String name) {
    final lowerName = name.toLowerCase();
    for (final key in _options.keys) {
      if (key.toLowerCase() == lowerName) {
        return _options[key];
      }
    }
    return null;
  }

  /// Verifica se esta constraint é funcionalmente equivalente a outra.
  bool isEquivalentTo(UniqueConstraint other) {
    final cols1Lower = getUnquotedColumns();
    final cols2Lower = other.getUnquotedColumns();
    if (!const ListEquality().equals(cols1Lower, cols2Lower)) {
      return false;
    }
    if (!const SetEquality()
        .equals(_flags.keys.toSet(), other._flags.keys.toSet())) {
      return false;
    }
    if (!const MapEquality().equals(_options, other._options)) {
      return false;
    }
    return true;
  }

  /// Cria uma cópia profunda desta constraint.
  UniqueConstraint clone() {
    return UniqueConstraint(
      name: name, // Nome original da classe base
      columns:
          List.from(_columns.keys), // Cria cópia da lista de nomes de coluna
      flags: List.from(_flags.keys), // Cria cópia da lista de flags
      options: Map.from(_options), // Cria cópia do mapa de opções
    );
  }

  /// Define o nome da constraint, atualizando o estado interno.
  /// Necessário para consistência se Table.rename... for implementado.
  void setName(String newName) {
    setName(newName); // Reutiliza a lógica da classe base
  }

  /// Obtém o nome original como foi fornecido (pode incluir aspas).
  String getOriginalName() {
    return name;
  }
}
