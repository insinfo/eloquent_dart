import 'dart:collection';
import 'package:eloquent/eloquent.dart';
import 'abstract_asset.dart';
import 'package:collection/collection.dart';
import 'index.dart';
import 'identifier.dart';

/// Representa uma constraint de chave estrangeira em memória.
/// Alinhado com Doctrine\DBAL\Schema\ForeignKeyConstraint.
class ForeignKeyConstraint extends AbstractAsset {
  /// Colunas locais (nomes originais -> Identifier).
  /// Tornando mutável internamente para Table._updateColumnInIndexesAndFKs
  Map<String, Identifier> _localColumnNames;

  /// Nome da tabela estrangeira referenciada (como Identifier).
  /// Mantido final, pois renomear tabela referenciada por FK é complexo.
  final Identifier _foreignTableName;

  /// Colunas estrangeiras (nomes originais -> Identifier).
  /// Mantido final, pois alterar colunas referenciadas por FK é complexo.
  final Map<String, Identifier> _foreignColumnNames;

  /// Opções como onDelete, onUpdate (armazenadas em lowercase).
  final Map<String, dynamic> _options;

  /// Construtor principal.
  ForeignKeyConstraint({
    required String name,
    required List<String> localColumns,
    required String foreignTableName,
    required List<String> foreignColumns,
    Map<String, dynamic> options = const {},
  })  : // Inicializa os mapas/identifiers internos
        _localColumnNames = LinkedHashMap.fromEntries(
            localColumns.map((c) => MapEntry(c, Identifier(c)))),
        _foreignTableName = Identifier(foreignTableName),
        _foreignColumnNames = LinkedHashMap.fromEntries(
            foreignColumns.map((c) => MapEntry(c, Identifier(c)))),
        _options = Map.unmodifiable(Map.fromEntries(options.entries
            .map((e) => MapEntry(e.key.toLowerCase(), e.value)))),
        super() {
    // Usa setName da classe base
    setName(name);
    if (this._localColumnNames.isEmpty || this._foreignColumnNames.isEmpty) {
      throw ArgumentError(
          'Foreign key "$name" must specify at least one local and one foreign column.');
    }
    if (this._localColumnNames.length != this._foreignColumnNames.length) {
      throw ArgumentError(
          'Foreign key "$name" must have the same number of local and foreign columns.');
    }
  }

  /// Construtor de fábrica a partir de um comando Fluent do Blueprint.
  factory ForeignKeyConstraint.fromFluent(
      Fluent command, String defaultName, String table) {
    final name = command['index'] as String? ?? defaultName;
    final localColumns = List<String>.from(
        (command['columns'] as List<dynamic>? ?? []).map((c) => c.toString()));
    final foreignTable = command['on'] as String;
    final foreignColumns = List<String>.from(
        (command['references'] as List<dynamic>? ?? [])
            .map((c) => c.toString()));
    final options = <String, dynamic>{};
    if (command['onDelete'] != null) options['ondelete'] = command['onDelete'];
    if (command['onUpdate'] != null) options['onupdate'] = command['onUpdate'];

    return ForeignKeyConstraint(
      name: name,
      localColumns: localColumns,
      foreignTableName: foreignTable,
      foreignColumns: foreignColumns,
      options: options,
    );
  }

  // --- Getters para Nomes (retornam cópias imutáveis) ---
  List<String> getLocalColumns() => List.unmodifiable(_localColumnNames.keys);
  List<String> getQuotedLocalColumns(SchemaGrammar grammar) =>
      List.unmodifiable(
          _localColumnNames.values.map((id) => id.getQuotedName(grammar)));
  List<String> getUnquotedLocalColumns() => List.unmodifiable(
      _localColumnNames.keys.map((col) => trimQuotes(col).toLowerCase()));

  String getForeignTableName() => _foreignTableName.getOriginalName();
  String getQuotedForeignTableName(SchemaGrammar grammar) =>
      _foreignTableName.getQuotedName(grammar);
  String getUnquotedForeignTableName() =>
      _foreignTableName.getName().toLowerCase();

  List<String> getForeignColumns() =>
      List.unmodifiable(_foreignColumnNames.keys);
  List<String> getQuotedForeignColumns(SchemaGrammar grammar) =>
      List.unmodifiable(
          _foreignColumnNames.values.map((id) => id.getQuotedName(grammar)));
  List<String> getUnquotedForeignColumns() => List.unmodifiable(
      _foreignColumnNames.keys.map((col) => trimQuotes(col).toLowerCase()));

  // --- Getters e Métodos para Opções ---
  Map<String, dynamic> getOptions() => _options; // Já é imutável
  bool hasOption(String name) => _options.containsKey(name.toLowerCase());
  dynamic getOption(String name) => _options[name.toLowerCase()];
  String? getOnUpdate() =>
      _normalizeOnEventAction(getOption('onupdate') as String?);
  String? getOnDelete() =>
      _normalizeOnEventAction(getOption('ondelete') as String?);

  String? _normalizeOnEventAction(String? action) {
    if (action == null) return null;
    final upperAction = action.toUpperCase();
    if (upperAction == 'NO ACTION' || upperAction == 'RESTRICT') return null;
    return upperAction;
  }

  // --- Métodos de Comparação e Utilidade ---
  bool intersectsIndexColumns(Index index) {
    final indexColsLower = index.getUnquotedColumns();
    final localColsLower = getUnquotedLocalColumns();
    return indexColsLower.any((indexCol) => localColsLower.contains(indexCol));
  }

  bool isEquivalentTo(ForeignKeyConstraint other) {
    if (!const SetEquality().equals(Set.from(getUnquotedLocalColumns()),
        Set.from(other.getUnquotedLocalColumns()))) return false;
    if (!const SetEquality().equals(Set.from(getUnquotedForeignColumns()),
        Set.from(other.getUnquotedForeignColumns()))) return false;
    if (getUnquotedForeignTableName() != other.getUnquotedForeignTableName())
      return false;
    if (getOnDelete() != other.getOnDelete()) return false;
    if (getOnUpdate() != other.getOnUpdate()) return false;

    final options1Filtered = Map.from(_options)
      ..remove('ondelete')
      ..remove('onupdate');
    final options2Filtered = Map.from(other._options)
      ..remove('ondelete')
      ..remove('onupdate');
    if (!const MapEquality().equals(options1Filtered, options2Filtered))
      return false;

    return true;
  }

  /// Cria uma cópia profunda desta chave estrangeira.
  ForeignKeyConstraint clone() {
    return ForeignKeyConstraint(
      name: name, // Nome original da classe base
      localColumns:
          List.from(_localColumnNames.keys), // Cria cópia da lista de nomes
      foreignTableName:
          _foreignTableName.getOriginalName(), // Usa o nome original
      foreignColumns:
          List.from(_foreignColumnNames.keys), // Cria cópia da lista de nomes
      options: Map.from(
          _options), // Cria cópia do mapa de opções (já está lowercase)
    );
  }

  /// Define o nome da constraint, atualizando o estado interno.
  void setName(String newName) {
    setName(newName); // Reutiliza a lógica da classe base
  }

  /// Obtém o nome original como foi fornecido (pode incluir aspas).
  String getOriginalName() {
    return name;
  }
}
