import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';
import 'dart:async';

/// Representa um blueprint para definir ou modificar uma tabela no schema.
/// Mapeia a funcionalidade da classe Blueprint do Laravel/Illuminate.
class Blueprint {
  /// O nome da tabela que o blueprint descreve.
  final String _table;

  /// As colunas que devem ser adicionadas ou modificadas na tabela.
  final List<Fluent> _columns = [];

  /// Os comandos (ações) que devem ser executados na tabela.
  final List<Fluent> _commands = [];

  // --- Variáveis de Configuração da Tabela (Renomeadas) ---
  /// O storage engine a ser usado (ex: InnoDB). Acessado pela Gramática.
  String? tableEngine;

  /// O character set padrão para a tabela. Acessado pela Gramática.
  String? tableCharset;

  /// A collation padrão para a tabela. Acessado pela Gramática.
  String? tableCollation;
  // --- Fim ---

  /// Indica se a tabela deve ser temporária.
  bool temporaryV = false;

  /// Cria uma nova instância de Blueprint.
  Blueprint(String tableP, [Function(Blueprint)? callback]) : _table = tableP {
    if (callback != null) {
      callback(this);
    }
  }

  /// Executa o blueprint contra a conexão do banco de dados.
  Future<void> build(Connection connection, SchemaGrammar grammar) async {
    final statements = toSql(connection, grammar);
    for (final statement in statements) {
      // Usa `execute` para DDL pois geralmente não retorna linhas.
      await connection.execute(statement);
    }
  }

  /// Gera as instruções SQL para este blueprint.
  List<String> toSql(Connection connection, SchemaGrammar grammar) {
    addImpliedCommands();

    final statements = <String>[];
    for (final command in _commands) {
      final commandName = command['name'] as String;
      final method = 'compile${Utils.ucfirst(commandName)}';

      List<String>? sql;
      try {
        // Chama o método correspondente na gramática
        switch (method) {
          case 'compileCreate':
            sql = grammar.compileCreate(this, command, connection);
            break;
          case 'compileAdd':
            sql = grammar.compileAdd(this, command);
            break;
          case 'compilePrimary':
            sql = grammar.compilePrimary(this, command);
            break;
          case 'compileUnique':
            sql = grammar.compileUnique(this, command);
            break;
          case 'compileIndex':
            sql = grammar.compileIndex(this, command);
            break;
          case 'compileSpatialIndex':
            sql = grammar.compileSpatialIndex(this, command);
            break;
          case 'compileForeign':
            sql = grammar.compileForeign(this, command);
            break;
          case 'compileDrop':
            sql = grammar.compileDrop(this, command);
            break;
          case 'compileDropIfExists':
            sql = grammar.compileDropIfExists(this, command);
            break;
          case 'compileDropColumn':
            sql = grammar.compileDropColumn(this, command);
            break;
          case 'compileDropPrimary':
            sql = grammar.compileDropPrimary(this, command);
            break;
          case 'compileDropUnique':
            sql = grammar.compileDropUnique(this, command);
            break;
          case 'compileDropIndex':
            sql = grammar.compileDropIndex(this, command);
            break;
          case 'compileDropSpatialIndex':
            sql = grammar.compileDropSpatialIndex(this, command);
            break;
          case 'compileDropForeign':
            sql = grammar.compileDropForeign(this, command);
            break;
          case 'compileRename':
            sql = grammar.compileRename(this, command);
            break;
          case 'compileRenameIndex':
            sql = grammar.compileRenameIndex(this, command);
            break;
          case 'compileRenameColumn':
            sql = grammar.compileRenameColumn(this, command, connection);
            break;
          case 'compileChange':
            sql = grammar.compileChange(this, command, connection);
            break;
          // Adicionar compileDropRememberToken se necessário
          default:
            print(
                "Warning: Unknown command type '$commandName' in Blueprint.toSql");
        }
      } catch (e) {
        // Captura erros (especialmente UnimplementedError de gramáticas)
        print("Error compiling command '$commandName': $e");
      }

      if (sql != null && sql.isNotEmpty) {
        statements.addAll(sql);
      }
    }
    return statements;
  }

  /// Adiciona comandos implícitos (add, change) se necessário.
  @protected
  void addImpliedCommands() {
    // Adiciona 'add' se houver colunas novas e não for 'create'
    if (getAddedColumns().isNotEmpty && !creating()) {
      if (!_commands.any((cmd) => cmd['name'] == 'add')) {
        _commands.insert(0, createCommand('add'));
      }
    }
    // Adiciona 'change' se houver colunas modificadas e não for 'create'
    if (getChangedColumns().isNotEmpty && !creating()) {
      if (!_commands.any((cmd) => cmd['name'] == 'change')) {
        _commands.insert(0, createCommand('change'));
      }
    }
    // Adiciona comandos para índices definidos fluentemente nas colunas
    addFluentIndexes();
  }

  /// Adiciona comandos para índices definidos fluentemente nas colunas.
  @protected
  void addFluentIndexes() {
    // Itera sobre uma cópia para poder remover atributos do original com segurança
    for (final column in List.from(_columns)) {
      void checkAndAddIndex(String indexType, String commandName) {
        final indexValue = column[indexType];
        if (indexValue != null) {
          String? explicitName = (indexValue is String && indexValue.isNotEmpty)
              ? indexValue
              : null;
          // Adiciona o comando de índice de nível de tabela
          indexCommand(commandName, column['name'], explicitName);
          // Remove o atributo do Fluent original para não ser processado como modificador
          column.attributes.remove(indexType);
        }
      }

      checkAndAddIndex('primary', 'primary');
      checkAndAddIndex('unique', 'unique');
      checkAndAddIndex('index', 'index');
      checkAndAddIndex('spatialIndex', 'spatialIndex');
    }
  }

  /// Verifica se existe um comando 'create'.
  bool creating() => _commands.any((command) => command['name'] == 'create');

  /// Adiciona comando 'create'.
  Fluent create() => addCommand('create');

  /// Marca a tabela como temporária.
  void temporary() => temporaryV = true;

  /// Adiciona comando 'drop'.
  Fluent drop() => addCommand('drop');

  /// Adiciona comando 'dropIfExists'.
  Fluent dropIfExists() => addCommand('dropIfExists');

  /// Adiciona comando 'dropColumn'. Aceita String ou List<String>.
  Fluent dropColumn(dynamic columns) {
    final List<String> columnList;
    if (columns is String) {
      columnList = [columns];
    } else if (columns is List) {
      columnList = List<String>.from(columns.map((e) => e.toString()));
    } else {
      throw ArgumentError('dropColumn expects a String or a List<String>.');
    }
    // Adiciona 'dropColumn' com a lista de colunas nos parâmetros
    return addCommand('dropColumn', {'columns': columnList});
  }

  /// Adiciona comando 'renameColumn'.
  Fluent renameColumn(String from, String to) =>
      addCommand('renameColumn', {'from': from, 'to': to});

  /// Adiciona comando 'dropPrimary'.
  Fluent dropPrimary([dynamic index]) =>
      dropIndexCommand('dropPrimary', 'primary', index);

  /// Adiciona comando 'dropUnique'.
  Fluent dropUnique(String index) =>
      dropIndexCommand('dropUnique', 'unique', index);

  /// Adiciona comando 'dropIndex'.
  Fluent dropIndex(String index) =>
      dropIndexCommand('dropIndex', 'index', index);

  /// Adiciona comando 'dropSpatialIndex'.
  Fluent dropSpatialIndex(String index) =>
      dropIndexCommand('dropSpatialIndex', 'spatialIndex', index);

  /// Adiciona comando 'dropForeign'.
  Fluent dropForeign(String index) =>
      dropIndexCommand('dropForeign', 'foreign', index);

  /// Adiciona um comando para dropar um índice/constraint.
  @protected
  Fluent dropIndexCommand(String command, String type, dynamic index) {
    List<String>? columns;
    String? finalIndexName;

    if (index is List) {
      columns = List<String>.from(index.map((e) => e.toString()));
      finalIndexName = createIndexName(type, columns);
    } else if (index is String) {
      finalIndexName = index;
    } else if (index == null && command == 'dropPrimary') {
      finalIndexName = null; // Gramática lida com nome padrão
    } else if (index != null) {
      throw ArgumentError(
          "Index for dropping must be a String, List<String>, or null (for primary).");
    } else {
      throw ArgumentError(
          "Index name is required for dropping $type constraints/indexes.");
    }

    // Adiciona o comando com 'index' (nome) e opcionalmente 'columns'
    final parameters = <String, dynamic>{'index': finalIndexName};
    if (columns != null) parameters['columns'] = columns;
    return addCommand(command, parameters);
  }

  void dropTimestamps() => dropColumn(['created_at', 'updated_at']);
  void dropTimestampsTz() => dropTimestamps();
  void dropSoftDeletes({String column = 'deleted_at'}) => dropColumn(column);
  void dropSoftDeletesTz({String column = 'deleted_at'}) => dropColumn(column);

  /// Adiciona comando 'dropRememberToken' (específico).
  void dropRememberToken() => dropColumn(
      'remember_token'); // Adiciona comando específico se necessário pela gramática
  // OU apenas: dropColumn('remember_token'); se a gramática não precisar de comando especial

  Fluent rename(String to) => addCommand('rename', {'to': to});
  Fluent renameIndex(String from, String to) =>
      addCommand('renameIndex', {'from': from, 'to': to});

  // --- Métodos de Definição de Índices/Constraints (Nível de Tabela) ---
  Fluent primary(dynamic columns, [String? name]) =>
      indexCommand('primary', columns, name);
  Fluent unique(dynamic columns, [String? name]) =>
      indexCommand('unique', columns, name);
  Fluent index(dynamic columns, [String? name]) =>
      indexCommand('index', columns, name);
  Fluent spatialIndex(dynamic columns, [String? name]) =>
      indexCommand('spatialIndex', columns, name);

  /// Adiciona o comando 'foreign', retorna Fluent para encadear .references().on() etc.
  Fluent foreign(dynamic columns, [String? name]) =>
      indexCommand('foreign', columns, name);

  @protected
  Fluent indexCommand(String type, dynamic columns, String? index) {
    final columnList = (columns is List)
        ? List<String>.from(columns.map((e) => e.toString()))
        : [columns.toString()];

    // Gera nome padrão se não fornecido, exceto para foreign
    index ??= (type != 'foreign') ? createIndexName(type, columnList) : null;

    // Valida se o nome é obrigatório e não foi fornecido/gerado
    if (index == null && !['foreign', 'primary'].contains(type)) {
      throw ArgumentError("Index name is required for command type '$type'.");
    }

    return addCommand(type, {'index': index, 'columns': columnList});
  }

  @protected
  String createIndexName(String type, List<String> columns) {
    const int maxTotalLength = 63;
    final tableNamePart = _table.length > maxTotalLength ~/ 3
        ? _table.substring(0, maxTotalLength ~/ 3)
        : _table;
    final columnsPart = columns.join('_');
    final columnsPartShort = columnsPart.length > maxTotalLength ~/ 3
        ? columnsPart.substring(0, maxTotalLength ~/ 3)
        : columnsPart;
    final index = '${tableNamePart}_${columnsPartShort}_$type'.toLowerCase();
    String safeIndex = index
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), ''); // Remove underscores no início/fim
    if (safeIndex.isEmpty)
      safeIndex =
          '${type}_${columns.hashCode.abs().toRadixString(16)}'; // Fallback se tudo for removido
    if (safeIndex.length > maxTotalLength) {
      final hash = safeIndex.hashCode
          .abs()
          .toRadixString(16)
          .padLeft(6, '0')
          .substring(0, 6);
      safeIndex = '${safeIndex.substring(0, maxTotalLength - 7)}_$hash';
    }
    return safeIndex;
  }

  // --- Definições de Coluna (Métodos Builder) ---
  // (Implementações como antes, chamando addColumn)
  Fluent increments(String column) => unsignedBigInteger(column, true);
  Fluent tinyIncrements(String column) => unsignedTinyInteger(column, true);
  Fluent smallIncrements(String column) => unsignedSmallInteger(column, true);
  Fluent mediumIncrements(String column) => unsignedMediumInteger(column, true);
  Fluent bigIncrements(String column) => unsignedBigInteger(column, true);
  Fluent id([String column = 'id']) => unsignedBigInteger(column, true);
  Fluent char(String column, [int length = 255]) =>
      addColumn('char', column, {'length': length});
  Fluent string(String column, [int length = 255]) =>
      addColumn('string', column, {'length': length});
  Fluent text(String column) => addColumn('text', column);
  Fluent mediumText(String column) => addColumn('mediumText', column);
  Fluent longText(String column) => addColumn('longText', column);
  Fluent integer(String column,
          [bool autoIncrement = false, bool unsigned = false]) =>
      addColumn('integer', column,
          {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  Fluent tinyInteger(String column,
          [bool autoIncrement = false, bool unsigned = false]) =>
      addColumn('tinyInteger', column,
          {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  Fluent smallInteger(String column,
          [bool autoIncrement = false, bool unsigned = false]) =>
      addColumn('smallInteger', column,
          {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  Fluent mediumInteger(String column,
          [bool autoIncrement = false, bool unsigned = false]) =>
      addColumn('mediumInteger', column,
          {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  Fluent bigInteger(String column,
          [bool autoIncrement = false, bool unsigned = false]) =>
      addColumn('bigInteger', column,
          {'autoIncrement': autoIncrement, 'unsigned': unsigned});
  Fluent unsignedInteger(String column, [bool autoIncrement = false]) =>
      integer(column, autoIncrement, true);
  Fluent unsignedTinyInteger(String column, [bool autoIncrement = false]) =>
      tinyInteger(column, autoIncrement, true);
  Fluent unsignedSmallInteger(String column, [bool autoIncrement = false]) =>
      smallInteger(column, autoIncrement, true);
  Fluent unsignedMediumInteger(String column, [bool autoIncrement = false]) =>
      mediumInteger(column, autoIncrement, true);
  Fluent unsignedBigInteger(String column, [bool autoIncrement = false]) =>
      bigInteger(column, autoIncrement, true);
  Fluent unsignedId([String column = 'id']) => unsignedBigInteger(column, true);
  Fluent foreignId(String column) =>
      addColumn('bigInteger', column, {'unsigned': true});
  Fluent foreignIdFor(Type modelType, [String? column]) {
    final className = modelType.toString();
    final defaultColumnName = '${Utils.toSnakeCase(className)}_id';
    return foreignId(column ?? defaultColumnName);
  }

  Fluent float(String column, [int total = 8, int places = 2]) =>
      addColumn('float', column, {'total': total, 'places': places});
  Fluent double(String column, [int? total, int? places]) =>
      addColumn('double', column, {'total': total, 'places': places});
  Fluent decimal(String column, [int total = 8, int places = 2]) =>
      addColumn('decimal', column, {'total': total, 'places': places});
  Fluent unsignedDecimal(String column, [int total = 8, int places = 2]) =>
      addColumn('decimal', column,
          {'total': total, 'places': places, 'unsigned': true});
  Fluent boolean(String column) => addColumn('boolean', column);
  Fluent enumeration(String column, List<String> allowed) =>
      addColumn('enum', column, {'allowed': allowed});
  Fluent json(String column) => addColumn('json', column);
  Fluent jsonb(String column) => addColumn('jsonb', column);
  Fluent date(String column) => addColumn('date', column);
  Fluent dateTime(String column, {int precision = 0}) =>
      addColumn('dateTime', column, {'precision': precision});
  Fluent dateTimeTz(String column, {int precision = 0}) =>
      addColumn('dateTimeTz', column, {'precision': precision});
  Fluent time(String column, {int precision = 0}) =>
      addColumn('time', column, {'precision': precision});
  Fluent timeTz(String column, {int precision = 0}) =>
      addColumn('timeTz', column, {'precision': precision});
  Fluent timestamp(String column, {int precision = 0}) =>
      addColumn('timestamp', column, {'precision': precision});
  Fluent timestampTz(String column, {int precision = 0}) =>
      addColumn('timestampTz', column, {'precision': precision});

  /// Adiciona colunas 'created_at' e 'updated_at' nullable.
  void nullableTimestamps({int precision = 0}) {
    timestamp('created_at', precision: precision);
    this.nullable();
    timestamp('updated_at', precision: precision);
    this.nullable();
  }

  /// Adiciona colunas 'created_at' e 'updated_at'.
  void timestamps({int precision = 0}) {
    timestamp('created_at', precision: precision);
    timestamp('updated_at', precision: precision);
  }

  /// Adiciona colunas 'created_at' e 'updated_at' com timezone.
  void timestampsTz({int precision = 0}) {
    timestampTz('created_at', precision: precision);
    timestampTz('updated_at', precision: precision);
  }

  /// Adiciona coluna 'deleted_at' nullable para soft deletes.
  Fluent softDeletes({String column = 'deleted_at', int precision = 0}) {
    timestamp(column, precision: precision);
    return this.nullable();
  }

  /// Adiciona coluna 'deleted_at' nullable com timezone para soft deletes.
  Fluent softDeletesTz({String column = 'deleted_at', int precision = 0}) {
    timestampTz(column, precision: precision);
    return this.nullable();
  }

  Fluent binary(String column) => addColumn('binary', column);
  Fluent uuid(String column) => addColumn('uuid', column);
  Fluent foreignUuid(String column) => addColumn('uuid', column);
  Fluent ipAddress(String column) => addColumn('ipAddress', column);
  Fluent macAddress(String column) => addColumn('macAddress', column);
  Fluent geometry(String column) => addColumn('geometry', column);
  Fluent point(String column, {int? srid}) =>
      addColumn('point', column, {'srid': srid});
  Fluent lineString(String column, {int? srid}) =>
      addColumn('lineString', column, {'srid': srid});
  Fluent polygon(String column, {int? srid}) =>
      addColumn('polygon', column, {'srid': srid});
  Fluent geometryCollection(String column, {int? srid}) =>
      addColumn('geometryCollection', column, {'srid': srid});
  Fluent multiPoint(String column, {int? srid}) =>
      addColumn('multiPoint', column, {'srid': srid});
  Fluent multiLineString(String column, {int? srid}) =>
      addColumn('multiLineString', column, {'srid': srid});
  Fluent multiPolygon(String column, {int? srid}) =>
      addColumn('multiPolygon', column, {'srid': srid});
  void morphs(String name, [String? indexName]) {
    unsignedBigInteger("${name}_id");
    string("${name}_type");
    index(["${name}_id", "${name}_type"], indexName);
  }

  void nullableMorphs(String name, [String? indexName]) {
    unsignedBigInteger("${name}_id");
    this.nullable();
    string("${name}_type");
    this.nullable();
    index(["${name}_id", "${name}_type"], indexName);
  }

  void uuidMorphs(String name, [String? indexName]) {
    uuid("${name}_id");
    string("${name}_type");
    index(["${name}_id", "${name}_type"], indexName);
  }

  void nullableUuidMorphs(String name, [String? indexName]) {
    uuid("${name}_id");
    this.nullable();
    string("${name}_type");
    this.nullable();
    index(["${name}_id", "${name}_type"], indexName);
  }

  Fluent rememberToken() {
    addColumn('string', 'remember_token', {'length': 100});
    return nullable();
  }

  // --- Métodos Internos ---
  @protected
  Fluent addColumn(String type, String name,
      [Map<String, dynamic> parameters = const {}]) {
    final attributes = {
      'type': type,
      'name': name,
      'change': false,
      ...parameters
    };
    final column = Fluent(attributes);
    _columns.add(column);
    return column;
  }

  @protected
  void removeColumn(String name) {
    _columns.removeWhere((col) => col['name'] == name);
  }

  @protected
  Fluent addCommand(String name, [Map<String, dynamic>? parameters]) {
    final command = createCommand(name, parameters);
    _commands.add(command);
    return command;
  }

  @protected
  Fluent createCommand(String name, [Map<String, dynamic>? parameters]) {
    return Fluent({'name': name, ...?parameters});
  }

  // --- Getters ---
  String getTable() => _table;
  List<Fluent> getColumns() => List.unmodifiable(_columns);
  List<Fluent> getCommands() => List.unmodifiable(_commands);
  List<Fluent> getAddedColumns() =>
      _columns.where((c) => c['change'] != true).toList();
  List<Fluent> getChangedColumns() =>
      _columns.where((c) => c['change'] == true).toList();

  // --- Chaining para Modificadores (Operam no último Fluent da coluna adicionada) ---
  Fluent _getLastColumnFluent() {
    if (_columns.isEmpty) throw StateError("No column defined yet.");
    return _columns.last;
  }

  Fluent nullable([bool value = true]) {
    final col = _getLastColumnFluent();
    col['nullable'] = value;
    return col;
  }

  Fluent useCurrent() {
    final col = _getLastColumnFluent();
    col['useCurrent'] = true;
    return col;
  }

  Fluent useCurrentOnUpdate() {
    final col = _getLastColumnFluent();
    col['useCurrentOnUpdate'] = true;
    return col;
  }

  Fluent defaultTo(dynamic value) {
    final col = _getLastColumnFluent();
    col['default'] = value;
    return col;
  }

  Fluent unsigned() {
    final col = _getLastColumnFluent();
    col['unsigned'] = true;
    return col;
  }

  Fluent comment(String comment) {
    final col = _getLastColumnFluent();
    col['comment'] = comment;
    return col;
  }

  Fluent after(String column) {
    final col = _getLastColumnFluent();
    col['after'] = column;
    return col;
  }

  Fluent first() {
    final col = _getLastColumnFluent();
    col['first'] = true;
    return col;
  }

  Fluent storedAs(String expression) {
    final col = _getLastColumnFluent();
    col['storedAs'] = expression;
    return col;
  }

  Fluent virtualAs(String expression) {
    final col = _getLastColumnFluent();
    col['virtualAs'] = expression;
    return col;
  }

  Fluent charset(String charset) {
    final col = _getLastColumnFluent();
    col['charset'] = charset;
    return col;
  }

  Fluent collation(String collation) {
    final col = _getLastColumnFluent();
    col['collation'] = collation;
    return col;
  }

  Fluent srid(int srid) {
    final col = _getLastColumnFluent();
    col['srid'] = srid;
    return col;
  }

  Fluent change() {
    if (_columns.isNotEmpty) {
      _columns.last['change'] = true;
    }
    return _getLastColumnFluent();
  }

  // --- Chaining para Foreign Keys (Operam no último comando 'foreign' adicionado) ---
  Fluent _getLastCommandFluent(String expectedName) {
    if (_commands.isEmpty || _commands.last['name'] != expectedName)
      throw StateError(
          "Cannot apply foreign key modifier. Last command was not '$expectedName'.");
    return _commands.last;
  }

  Fluent references(dynamic columns) {
    final command = _getLastCommandFluent('foreign');
    command['references'] = (columns is List)
        ? List<String>.from(columns.map((e) => e.toString()))
        : [columns.toString()];
    return command;
  }

  Fluent on(String table) {
    final command = _getLastCommandFluent('foreign');
    command['on'] = table;
    return command;
  }

  Fluent onDelete(String action) {
    final command = _getLastCommandFluent('foreign');
    command['onDelete'] = action.toUpperCase();
    return command;
  }

  Fluent onUpdate(String action) {
    final command = _getLastCommandFluent('foreign');
    command['onUpdate'] = action.toUpperCase();
    return command;
  }

  Fluent deferrable([bool value = true]) {
    final command = _getLastCommandFluent('foreign');
    command['deferrable'] = value;
    return command;
  }

  Fluent initiallyImmediate([bool value = true]) {
    final command = _getLastCommandFluent('foreign');
    command['initiallyImmediate'] = value;
    return command;
  }

  Fluent notDeferrable() => deferrable(false);
  Fluent initiallyDeferred() => initiallyImmediate(false);
}
