import 'package:eloquent/eloquent.dart';
import 'abstract_asset.dart';
import 'package:collection/collection.dart';

/// Representa um índice de banco de dados em memória, aprimorado para
/// suportar introspecção e comparação de schemas.
/// Inspirado em Doctrine\DBAL\Schema\Index.
class Index extends AbstractAsset {
  /// Colunas que compõem o índice (nomes originais).
  /// Tornando mutável internamente para permitir atualização em `Table._updateColumnInIndexesAndFKs`.
  /// Getters retornarão cópias imutáveis.
  List<String> _columns;

  /// Se o índice garante unicidade.
  bool isUnique;

  /// Se o índice é a chave primária.
  bool isPrimary;

  /// Flags específicos da plataforma (ex: 'CLUSTERED', 'DESC').
  /// Armazenados em lowercase para comparação case-insensitive.
  Set<String> _flags;

  /// Opções específicas da plataforma (ex: 'where' para índice parcial).
  Map<String, dynamic> _options;

  /// Construtor principal.
  Index({
    required String name,
    required List<String> columns,
    this.isUnique = false,
    this.isPrimary = false,
    List<String> flags = const [],
    Map<String, dynamic> options = const {},
  })  : // Inicializa as propriedades mutáveis com cópias
        this._columns = List.from(columns),
        this._flags = Set.from(flags.map((f) => f.toLowerCase())),
        this._options = Map.from(options) {
    // Usa o método setName da classe base para inicializar _name e _quoted
    setName(name); // <-- Usa setName
    if (this.isPrimary && !this.isUnique) {
      throw ArgumentError('Primary key index "$name" must also be unique.');
    }
    if (this._columns.isEmpty) {
      throw ArgumentError('Index "$name" must span at least one column.');
    }
  }

  /// Construtor de fábrica a partir de um comando Fluent do Blueprint.
  factory Index.fromFluent(Fluent command, String defaultName, String table) {
    final name = command['index'] as String? ?? defaultName;
    final columns = List<String>.from(
        (command['columns'] as List<dynamic>? ?? []).map((c) => c.toString()));
    final commandName = command['name']?.toString().toLowerCase();
    final isPrimaryCmd = commandName == 'primary';
    final isUniqueCmd = commandName == 'unique' || isPrimaryCmd;
    final flags = List<String>.from(
        (command['flags'] as List<dynamic>? ?? []).map((f) => f.toString()));
    final options = Map<String, dynamic>.from(command['options'] as Map? ?? {});

    return Index(
      name: name,
      columns: columns,
      isPrimary: isPrimaryCmd,
      isUnique: isUniqueCmd,
      flags: flags,
      options: options,
    );
  }

  // --- Getters (retornam cópias imutáveis) ---

  List<String> getColumns() {
    return List.unmodifiable(_columns);
  }

  List<String> getQuotedColumns(SchemaGrammar grammar) {
    return List.unmodifiable(_columns.map((col) => grammar.wrap(col)));
  }

  List<String> getUnquotedColumns() {
    // Retorna sem aspas e em lowercase para comparação
    return List.unmodifiable(
        _columns.map((col) => trimQuotes(col).toLowerCase()));
  }

  List<String> getFlags() {
    return List.unmodifiable(_flags.toList());
  }

  Map<String, dynamic> getOptions() {
    return Map.unmodifiable(_options);
  }

  bool allowsDuplicates() {
    return !isUnique;
  }

  // --- Métodos de Verificação ---

  bool hasFlag(String flag) {
    return _flags.contains(flag.toLowerCase());
  }

  bool hasOption(String name) {
    return _options.containsKey(name);
  }

  dynamic getOption(String name) {
    return _options[name];
  }

  /// Verifica se este índice cobre (pelo menos) as colunas fornecidas na ordem correta,
  /// ignorando case.
  bool spansColumns(List<String> columnNames) {
    if (columnNames.isEmpty || columnNames.length > _columns.length) {
      return false;
    }
    final currentColsLower =
        _columns.map((c) => c.toLowerCase()).toList(); // Usa a lista interna
    final targetColsLower = columnNames.map((c) => c.toLowerCase()).toList();

    for (int i = 0; i < targetColsLower.length; i++) {
      if (currentColsLower[i] != targetColsLower[i]) {
        return false;
      }
    }
    return true;
  }

  /// Verifica se este índice é funcionalmente equivalente a outro índice.
  bool isFulfilledBy(Index other) {
    if (isPrimary != other.isPrimary || isUnique != other.isUnique) {
      return false;
    }
    // Compara as colunas internas diretamente (já que spansColumns usa lowercase)
    if (_columns.length != other._columns.length ||
        !spansColumns(other._columns)) {
      return false;
    }
    // Compara flags e options
    if (!const SetEquality().equals(_flags, other._flags)) return false;
    if (!const MapEquality().equals(_options, other._options)) return false;

    return true;
  }

  /// Cria uma cópia profunda deste índice.
  Index clone() {
    return Index(
      name: name, // Nome original da classe base
      columns: List.from(_columns), // Cria cópia da lista interna
      isUnique: isUnique,
      isPrimary: isPrimary,
      flags: List.from(_flags), // Cria cópia da lista de flags (do Set interno)
      options: Map.from(_options), // Cria cópia do mapa de opções
    );
  }

  /// Define o nome do índice, atualizando o estado interno.
  /// Necessário para Table.renameIndex.
  void setName(String newName) {
    setName(newName); // Reutiliza a lógica da classe base
  }

  /// Obtém o nome original como foi fornecido (pode incluir aspas).
  /// Usa a propriedade _name da classe base.
  String getOriginalName() {
    return name;
  }
}
