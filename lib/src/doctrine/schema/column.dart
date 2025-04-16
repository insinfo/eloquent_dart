import 'package:eloquent/eloquent.dart';
import 'abstract_asset.dart';

/// Representa uma coluna de banco de dados em memória, aprimorada para
/// suportar introspecção e comparação de schemas.
/// Inspirado em Doctrine\DBAL\Schema\Column.
class Column extends AbstractAsset {
  /// Tipo da coluna (nome genérico, ex: 'integer', 'string', 'enum').
  final String typeName;

  /// Comprimento (para varchar, char, etc.).
  int? length;

  /// Precisão total (para decimal, float, double). Doctrine usa 10 como padrão.
  int? precision = 10; // Doctrine default

  /// Número de casas decimais (para decimal, float, double). Doctrine usa 0 como padrão.
  int scale = 0; // Doctrine default

  /// Se o tipo numérico é sem sinal (UNSIGNED - específico do DB, ex: MySQL).
  bool unsigned = false;

  /// Se o tipo de string tem comprimento fixo (CHAR vs VARCHAR).
  bool fixed = false;

  /// Se a coluna NÃO permite valores NULL (NOT NULL). Oposto de 'nullable'.
  bool notnull = true;

  /// Valor padrão da coluna. Pode ser literal ou QueryExpression.
  dynamic defaultValue;

  /// Se a coluna é auto-incremento (SERIAL, AUTO_INCREMENT).
  bool autoIncrement = false;

  /// Comentário associado à coluna.
  String? comment;

  /// Collation específico para a coluna.
  String? collation;

  /// SRID para tipos de dados espaciais (GIS).
  int? srid;

  /// Valores permitidos para colunas do tipo ENUM.
  List<String>? allowedValues;

  /// Definição SQL bruta da coluna (sobrescreve outras propriedades se definido).
  String? columnDefinition;

  /// Opções específicas da plataforma (para detalhes não cobertos pelas props padrão).
  Map<String, dynamic> platformOptions = {};

  /// Construtor principal.
  Column(String name, this.typeName,
      {Map<String, dynamic> options = const {}}) {
    // Usa setName da classe base para inicializar _name e _quoted
    setName(name); // <-- CORRIGIDO: Usar setName aqui
    processOptions(options);

    if (autoIncrement) {
      notnull = true;
    }
  }

  /// Construtor de fábrica a partir de um objeto Fluent (usado no Blueprint).
  factory Column.fromFluent(Fluent fluent) {
    final Map<String, dynamic> attributes =
        Map<String, dynamic>.from(fluent.getAttributes());
    final name = attributes.remove('name') as String;
    final type = attributes.remove('type') as String;
    return Column(name, type, options: attributes);
  }

  /// Processa o mapa de opções para definir as propriedades da coluna.
  /// (Manter a implementação anterior deste método)
  void processOptions(Map<String, dynamic> options) {
    length = options['length'] as int? ?? length;
    precision =
        options['total'] as int? ?? options['precision'] as int? ?? precision;
    scale = options['places'] as int? ?? options['scale'] as int? ?? scale;
    unsigned = options['unsigned'] as bool? ?? unsigned;
    fixed = options['fixed'] as bool? ?? fixed;
    if (options.containsKey('nullable')) {
      notnull = !(options['nullable'] as bool? ?? false);
    } else if (options.containsKey('notnull')) {
      notnull = options['notnull'] as bool? ?? notnull;
    }
    defaultValue = options['default'] ?? defaultValue;
    autoIncrement = options['autoIncrement'] as bool? ?? autoIncrement;
    comment = options['comment'] as String? ?? comment;
    collation = options['collation'] as String? ?? collation;
    srid = options['srid'] as int? ?? srid;
    if (options.containsKey('allowed')) {
      final allowed = options['allowed'];
      if (allowed is List)
        allowedValues = List<String>.from(allowed.map((e) => e.toString()));
    } else if (options.containsKey('allowedValues')) {
      final allowed = options['allowedValues'];
      if (allowed is List<String>)
        allowedValues = allowed;
      else if (allowed is List)
        allowedValues = List<String>.from(allowed.map((e) => e.toString()));
    }
    columnDefinition =
        options['columnDefinition'] as String? ?? columnDefinition;
    platformOptions =
        options['platformOptions'] as Map<String, dynamic>? ?? platformOptions;
  }

  // --- Getters Públicos (manter os existentes) ---
  String get type => typeName;
  bool get isNullable => !notnull;
  int? get getLength => length;
  int get getPrecision => precision ?? 10;
  int get getScale => scale;
  bool get isUnsigned => unsigned;
  bool get isFixed => fixed;
  bool get isNotNull => notnull;
  dynamic get getDefaultValue => defaultValue;
  bool get isAutoIncrement => autoIncrement;
  String? get getComment => comment;
  String? get getCollation => collation;
  int? get getSrid => srid;
  List<String>? get getAllowedValues => allowedValues;
  String? get getColumnDefinition => columnDefinition;
  Map<String, dynamic> get getPlatformOptions =>
      Map.unmodifiable(platformOptions);

  /// Obtém o nome original como foi fornecido (pode incluir aspas).
  /// Usa a propriedade _name da classe base.
  String getOriginalName() {
    return name; // _name é herdado de SchemaAsset e definido por setName/_setName
  }

  /// Define o nome da coluna, atualizando o estado interno.
  /// Necessário para a funcionalidade de renomear coluna na classe Table.
  void setName(String newName) {
    setName(newName); // Reutiliza a lógica de _setName da classe base
  }

  // --- Métodos de Verificação e Conveniência (manter os existentes) ---
  bool hasPlatformOption(String name) => platformOptions.containsKey(name);
  dynamic getPlatformOption(String name) => platformOptions[name];
  bool isType(String name) => typeName.toLowerCase() == name.toLowerCase();
  bool get isNumericType {
    /* ... lógica existente ... */
    final numericTypes = {
      'integer',
      'tinyinteger',
      'smallinteger',
      'mediuminteger',
      'biginteger',
      'decimal',
      'float',
      'double',
      'int',
      'int2',
      'int4',
      'int8',
      'real',
      'numeric',
      'money'
    };
    return numericTypes.contains(typeName.toLowerCase());
  }

  bool get isStringType {
    /* ... lógica existente ... */
    final stringTypes = {
      'string',
      'char',
      'text',
      'mediumtext',
      'longtext',
      'varchar',
      'bpchar',
      'enum',
      'uuid'
    };
    return stringTypes.contains(typeName.toLowerCase());
  }

  bool get requiresLength {
    /* ... lógica existente ... */
    final typesRequiringLength = {
      'string',
      'char',
      'varchar',
      'bpchar',
      'binary'
    };
    return typesRequiringLength.contains(typeName.toLowerCase());
  }

  bool get requiresPrecisionScale {
    /* ... lógica existente ... */
    final typesRequiringPrecision = {'decimal', 'float', 'double', 'numeric'};
    return typesRequiringPrecision.contains(typeName.toLowerCase());
  }

  /// Converte a instância da coluna para um mapa de atributos.
  Map<String, dynamic> toArray() {
    return {
      'name': getName(), // Nome sem aspas
      'type': typeName,
      'length': length,
      'precision': getPrecision,
      'scale': getScale,
      'unsigned': unsigned,
      'fixed': fixed,
      'notnull': notnull,
      'default': defaultValue,
      'autoincrement': autoIncrement,
      'comment': comment,
      'collation': collation,
      'srid': srid,
      if (allowedValues != null) 'allowedValues': allowedValues,
      'columnDefinition': columnDefinition,
      ...platformOptions,
    };
  }

  /// Cria uma cópia profunda desta coluna.
  Column clone() {
    // Usa o construtor principal, passando o nome original e um mapa
    // de opções derivado do estado atual usando toArray().
    // toArray() já inclui todas as propriedades relevantes.
    final options = Map<String, dynamic>.from(toArray());
    // Remove 'name' e 'type' do mapa de opções, pois são passados separadamente
    options.remove('name');
    options.remove('type');

    // O construtor lida com a reatribuição das propriedades a partir das opções.
    return Column(getOriginalName(), typeName, options: options);
  }
}
