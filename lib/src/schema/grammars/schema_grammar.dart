//lib\src\schema\grammars\schema_grammar.dart
import 'package:eloquent/eloquent.dart';

import 'package:meta/meta.dart'; // Import for @protected if needed by subclasses

/// Representa a gramática base para manipulação de schemas de banco de dados.
/// Em PHP: \Illuminate\Database\Schema\Grammars\Grammar
///
/// Esta classe fornece a estrutura e métodos comuns, mas muitos detalhes
/// de sintaxe SQL específicos são deixados para as subclasses concretas
/// (ex: SchemaPostgresGrammar, SchemaMySqlGrammar).
abstract class SchemaGrammar extends BaseGrammar {
  /// Os possíveis modificadores de coluna que podem ser aplicados.
  final List<String> modifiers = const [
    'Unsigned',
    'Charset',
    'Collate',
    'VirtualAs',
    'StoredAs',
    'Nullable',
    'Default',
    'Incrementing',
    'Comment',
    'After',
    'First',
    'Srid',
  ];

  /// Os tipos de coluna que são considerados auto-incremento.
  final List<String> serials = const [
    'bigInteger',
    'integer',
    'mediumInteger',
    'smallInteger',
    'tinyInteger',
  ];

  late final Map<String, Function(Fluent)> typeCompilers;
  late final Map<String, Function(Blueprint, Fluent)> modifierCompilers;

  SchemaGrammar() {
    // Renomeado para evitar conflito com métodos de inicialização de subclasses
    typeCompilers = initializeTypeCompilersInternal();
    modifierCompilers = initializeModifierCompilers();
  }

  /// Inicializa o mapa de compiladores de tipo.
  @protected
  Map<String, Function(Fluent)> initializeTypeCompilersInternal() {
    // (Implementação como antes)
    return {
      'bigincrements': (c) => typeBigIncrements(c),
      'biginteger': (c) => typeBigInteger(c),
      'binary': (c) => typeBinary(c),
      'boolean': (c) => typeBoolean(c),
      'char': (c) => typeChar(c),
      'date': (c) => typeDate(c),
      'datetime': (c) => typeDateTime(c),
      'datetimetz': (c) => typeDateTimeTz(c),
      'decimal': (c) => typeDecimal(c),
      'double': (c) => typeDouble(c),
      'enum': (c) => typeEnum(c),
      'float': (c) => typeFloat(c),
      'geometry': (c) => typeGeometry(c),
      'geometrycollection': (c) => typeGeometryCollection(c),
      'increments': (c) => typeIncrements(c),
      'integer': (c) => typeInteger(c),
      'ipaddress': (c) => typeIpAddress(c),
      'json': (c) => typeJson(c),
      'jsonb': (c) => typeJsonb(c),
      'linestring': (c) => typeLineString(c),
      'longtext': (c) => typeLongText(c),
      'macaddress': (c) => typeMacAddress(c),
      'mediumincrements': (c) => typeMediumIncrements(c),
      'mediuminteger': (c) => typeMediumInteger(c),
      'mediumtext': (c) => typeMediumText(c),
      'morphs': (c) => typeMorphs(c),
      'multilinestring': (c) => typeMultiLineString(c),
      'multipoint': (c) => typeMultiPoint(c),
      'multipolygon': (c) => typeMultiPolygon(c),
      'nullablemorphs': (c) => typeNullableMorphs(c),
      'nullableuuidmorphs': (c) => typeNullableUuidMorphs(c),
      'point': (c) => typePoint(c),
      'polygon': (c) => typePolygon(c),
      'remembertoken': (c) => typeRememberToken(c),
      'smallincrements': (c) => typeSmallIncrements(c),
      'smallinteger': (c) => typeSmallInteger(c),
      'softdeletes': (c) => typeSoftDeletes(c),
      'softdeletestz': (c) => typeSoftDeletesTz(c),
      'string': (c) => typeString(c),
      'text': (c) => typeText(c),
      'time': (c) => typeTime(c),
      'timetz': (c) => typeTimeTz(c),
      'timestamp': (c) => typeTimestamp(c),
      'timestamptz': (c) => typeTimestampTz(c),
      'timestamps': (c) => typeTimestamps(c),
      'timestampstz': (c) => typeTimestampsTz(c),
      'tinyincrements': (c) => typeTinyIncrements(c),
      'tinyinteger': (c) => typeTinyInteger(c),
      'unsignedbiginteger': (c) => typeUnsignedBigInteger(c),
      'unsigneddecimal': (c) => typeUnsignedDecimal(c),
      'unsignedinteger': (c) => typeUnsignedInteger(c),
      'unsignedmediuminteger': (c) => typeUnsignedMediumInteger(c),
      'unsignedsmallinteger': (c) => typeUnsignedSmallInteger(c),
      'unsignedtinyinteger': (c) => typeUnsignedTinyInteger(c),
      'uuid': (c) => typeUuid(c),
      'uuidmorphs': (c) => typeUuidMorphs(c),
      'year': (c) => typeYear(c),
    };
  }

  /// Inicializa o mapa de compiladores de modificador.
  @protected
  Map<String, Function(Blueprint, Fluent)>
      initializeModifierCompilers() {
    // (Implementação como antes)
    return {
      'Nullable': (b, c) => modifyNullable(b, c),
      'Default': (b, c) => modifyDefault(b, c),
      'Unsigned': (b, c) => modifyUnsigned(b, c),
      'Comment': (b, c) => modifyComment(b, c),
      'First': (b, c) => modifyFirst(b, c),
      'After': (b, c) => modifyAfter(b, c),
      'StoredAs': (b, c) => modifyStoredAs(b, c),
      'VirtualAs': (b, c) => modifyVirtualAs(b, c),
      'Incrementing': (b, c) => modifyIncrementing(b, c),
      'Charset': (b, c) => modifyCharset(b, c),
      'Collate': (b, c) => modifyCollate(b, c),
      'Srid': (b, c) => modifySrid(b, c),
    };
  }

  // --- Métodos de Compilação de Comandos ---
  // (compileCreate, compileAdd, compilePrimary, etc. como antes, todos retornando List<String>)
  List<String> compileCreate(
      Blueprint blueprint, Fluent command, Connection connection) {
    /* ... */ return [''];
  }

  List<String> compileAdd(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compilePrimary(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileUnique(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileIndex(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileSpatialIndex(Blueprint blueprint, Fluent command) {
    return compileIndex(blueprint, command);
  }

  List<String> compileForeign(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDrop(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropIfExists(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropColumn(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropPrimary(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropUnique(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropIndex(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileDropSpatialIndex(Blueprint blueprint, Fluent command) {
    return compileDropIndex(blueprint, command);
  }

  List<String> compileDropForeign(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileRename(Blueprint blueprint, Fluent command) {
    /* ... */ return [''];
  }

  List<String> compileRenameIndex(Blueprint blueprint, Fluent command) {
    throw UnimplementedError(
        'Rename index requires database-specific implementation.');
  }

  List<String> compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    throw UnimplementedError(
        'Rename column requires database-specific implementation or schema introspection.');
  }

  List<String> compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    throw UnimplementedError(
        'Change column requires database-specific implementation or schema introspection.');
  }

  // --- NOVOS MÉTODOS ---

  /// Compila o comando SQL para habilitar restrições de chave estrangeira.
  /// Retorna uma lista vazia por padrão, indicando que não é suportado ou
  /// não há comando padrão. Subclasses devem sobrescrever.
  List<String> compileEnableForeignKeyConstraints() {
    print(
        "Warning: Enabling foreign key constraints is not supported by the default grammar.");
    return [];
  }

  /// Compila o comando SQL para desabilitar restrições de chave estrangeira.
  /// Retorna uma lista vazia por padrão, indicando que não é suportado ou
  /// não há comando padrão. Subclasses devem sobrescrever.
  List<String> compileDisableForeignKeyConstraints() {
    print(
        "Warning: Disabling foreign key constraints is not supported by the default grammar.");
    return [];
  }

  // --- FIM DOS NOVOS MÉTODOS ---

  // --- Métodos Helpers e Implementações de Tipos/Modificadores ---
  // (getCommandsByName, getCommandByName, getColumns, addModifiers, getType,
  //  type*, modify*, prefixArray, wrapTable, wrap, wrapValue, getDefaultValue,
  //  compileTableExists, compileColumnExists, Doctrine stubs... como antes)

  @protected
  String compileCreateTable(
      Blueprint blueprint, Fluent command, Connection connection) {
    /* ... */ return '';
  }

  @protected
  String compileCreateEngine(
      String sql, Connection connection, Blueprint blueprint) {
    return sql;
  }

  @protected
  String compileCreateCharset(
      String sql, Connection connection, Blueprint blueprint) {
    return sql;
  }

  @protected
  String compileCreateCollation(
      String sql, Connection connection, Blueprint blueprint) {
    return sql;
  }

  @protected
  List<Fluent> getCommandsByName(Blueprint blueprint, String name) {
    return [];
  }

  @protected
  Fluent? getCommandByName(Blueprint blueprint, String name) {
    return null;
  }

  @protected
  List<String> getColumns(Blueprint blueprint) {
    return [];
  }

  @protected
  String addModifiers(String sql, Blueprint blueprint, Fluent column) {
    return sql;
  }

  @protected
  String? getType(Fluent column) {
    return null;
  }

  String typeChar(Fluent column) => 'char(${column['length']})';
  String typeString(Fluent column) => 'varchar(${column['length']})';
  String typeText(Fluent column) => 'text';
  String typeMediumText(Fluent column) => 'mediumtext';
  String typeLongText(Fluent column) => 'longtext';
  String typeInteger(Fluent column) => 'integer';
  String typeTinyInteger(Fluent column) => 'tinyint';
  String typeSmallInteger(Fluent column) => 'smallint';
  String typeMediumInteger(Fluent column) => 'mediumint';
  String typeBigInteger(Fluent column) => 'bigint';
  String typeFloat(Fluent column) =>
      (column['total'] != null && column['places'] != null)
          ? 'float(${column['total']}, ${column['places']})'
          : 'float';
  String typeDouble(Fluent column) =>
      (column['total'] != null && column['places'] != null)
          ? 'double(${column['total']}, ${column['places']})'
          : 'double precision';
  String typeDecimal(Fluent column) =>
      'decimal(${column['total']}, ${column['places']})';
  String typeUnsignedDecimal(Fluent column) => typeDecimal(column);
  String typeBoolean(Fluent column) => 'boolean';
  String typeEnum(Fluent column) {
    final allowed = (column['allowed'] as List)
        .map((e) => "'${e.toString().replaceAll("'", "''")}'")
        .join(',');
    return 'enum($allowed)';
  }

  String typeJson(Fluent column) => 'json';
  String typeJsonb(Fluent column) => 'jsonb';
  String typeDate(Fluent column) => 'date';
  String typeDateTime(Fluent column) => 'timestamp';
  String typeDateTimeTz(Fluent column) => 'timestamp with time zone';
  String typeTime(Fluent column) => 'time';
  String typeTimeTz(Fluent column) => 'time with time zone';
  String typeTimestamp(Fluent column) => 'timestamp';
  String typeTimestampTz(Fluent column) => 'timestamp with time zone';
  String typeYear(Fluent column) => 'year';
  String typeBinary(Fluent column) => 'blob';
  String typeUuid(Fluent column) => 'uuid';
  String typeIpAddress(Fluent column) => 'varchar(45)';
  String typeMacAddress(Fluent column) => 'varchar(17)';
  String typeGeometry(Fluent column) => 'geometry';
  String typePoint(Fluent column) => 'point';
  String typeLineString(Fluent column) => 'linestring';
  String typePolygon(Fluent column) => 'polygon';
  String typeGeometryCollection(Fluent column) => 'geometrycollection';
  String typeMultiPoint(Fluent column) => 'multipoint';
  String typeMultiLineString(Fluent column) => 'multilinestring';
  String typeMultiPolygon(Fluent column) => 'multipolygon';
  String typeIncrements(Fluent column) => typeInteger(column);
  String typeTinyIncrements(Fluent column) => typeTinyInteger(column);
  String typeSmallIncrements(Fluent column) => typeSmallInteger(column);
  String typeMediumIncrements(Fluent column) => typeMediumInteger(column);
  String typeBigIncrements(Fluent column) => typeBigInteger(column);
  String typeUnsignedInteger(Fluent column) => typeInteger(column);
  String typeUnsignedTinyInteger(Fluent column) => typeTinyInteger(column);
  String typeUnsignedSmallInteger(Fluent column) => typeSmallInteger(column);
  String typeUnsignedMediumInteger(Fluent column) => typeMediumInteger(column);
  String typeUnsignedBigInteger(Fluent column) => typeBigInteger(column);
  String typeRememberToken(Fluent column) =>
      typeString(column..attributes['length'] = 100);
  String typeSoftDeletes(Fluent column) =>
      typeTimestamp(column..attributes['nullable'] = true);
  String typeSoftDeletesTz(Fluent column) =>
      typeTimestampTz(column..attributes['nullable'] = true);
  String typeMorphs(Fluent column) =>
      throw UnsupportedError('Morphs type handled by Blueprint.');
  String typeNullableMorphs(Fluent column) =>
      throw UnsupportedError('NullableMorphs type handled by Blueprint.');
  String typeUuidMorphs(Fluent column) =>
      throw UnsupportedError('UuidMorphs type handled by Blueprint.');
  String typeNullableUuidMorphs(Fluent column) =>
      throw UnsupportedError('NullableUuidMorphs type handled by Blueprint.');
  String typeTimestamps(Fluent column) =>
      throw UnsupportedError('Timestamps type handled by Blueprint.');
  String typeTimestampsTz(Fluent column) =>
      throw UnsupportedError('TimestampsTz type handled by Blueprint.');
  @protected
  String? modifyNullable(Blueprint blueprint, Fluent column) {
    /* ... */ return '...';
  }

  @protected
  String? modifyDefault(Blueprint blueprint, Fluent column) {
    /* ... */ return '...';
  }

  @protected
  String? modifyUnsigned(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyIncrementing(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyComment(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyFirst(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyAfter(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyStoredAs(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyVirtualAs(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyCharset(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  String? modifyCollate(Blueprint blueprint, Fluent column) {
    /* ... */ return '...';
  }

  @protected
  String? modifySrid(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  List<String> prefixArray(String prefix, List values) {
    /* ... */ return [];
  }

  @override
  String wrapTable(dynamic table) {
    /* ... */ return '';
  }

  @override
  String wrap(dynamic value, [bool prefixAlias = false]) {
    /* ... */ return '';
  }

  @override
  String wrapValue(String value) {
    /* ... */ return '';
  }

  @protected
  String getDefaultValue(dynamic value) {
    /* ... */ return '';
  }

  String compileTableExists() {
    /* ... */ return '';
  }

  String compileColumnExists(String table) {
    /* ... */ return '';
  }

  dynamic getDoctrineTableDiff(Blueprint blueprint, dynamic schema) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getRenamedDiff(Blueprint blueprint, Fluent command, dynamic column,
          dynamic schema) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic setRenamedColumns(
          dynamic tableDiff, Fluent command, dynamic column) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getChangedDiff(Blueprint blueprint, dynamic schema) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getTableWithColumnChanges(Blueprint blueprint, dynamic table) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getDoctrineColumnForChange(dynamic table, Fluent fluent) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getDoctrineColumnChangeOptions(Fluent fluent) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic getDoctrineColumnType(String type) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic calculateDoctrineTextLength(String type) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic mapFluentOptionToDoctrine(String attribute) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
  dynamic mapFluentValueToDoctrine(String option, dynamic value) =>
      throw UnimplementedError('Doctrine DBAL features are not available.');
}
