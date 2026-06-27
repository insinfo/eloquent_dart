//lib\src\schema\grammars\schema_grammar.dart
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/schema/abstract_schema_manager.dart';
import 'package:eloquent/src/doctrine/schema/column.dart';
import 'package:eloquent/src/doctrine/schema/comparator.dart';
import 'package:eloquent/src/doctrine/schema/foreign_key_constraint.dart';
import 'package:eloquent/src/doctrine/schema/index.dart';
import 'package:eloquent/src/doctrine/schema/table.dart';
import 'package:eloquent/src/doctrine/schema/table_diff.dart';
import 'package:eloquent/src/doctrine/schema/unique_constraint.dart';

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
  Map<String, Function(Blueprint, Fluent)> initializeModifierCompilers() {
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
    return blueprint.getAddedColumns().map((column) {
      final sql = '${wrap(column)} ${getType(column)}';
      return addModifiers(sql, blueprint, column);
    }).toList();
  }

  @protected
  String addModifiers(String sql, Blueprint blueprint, Fluent column) {
    for (final modifier in modifiers) {
      final compiler = modifierCompilers[modifier];
      if (compiler == null) {
        continue;
      }

      final value = compiler(blueprint, column);
      if (value != null && value.toString().isNotEmpty) {
        sql += value.toString();
      }
    }

    return sql;
  }

  @protected
  String? getType(Fluent column) {
    final type = column['type']?.toString().toLowerCase();
    if (type == null) {
      return null;
    }

    final compiler = typeCompilers[type];
    if (compiler == null) {
      throw UnsupportedError('Column type "$type" is not supported.');
    }

    return compiler(column).toString();
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
    if (!column.attributes.containsKey('nullable')) {
      return null;
    }

    return column['nullable'] == true ? ' null' : ' not null';
  }

  @protected
  String? modifyDefault(Blueprint blueprint, Fluent column) {
    if (!column.attributes.containsKey('default')) {
      return null;
    }

    return ' default ${getDefaultValue(column['default'])}';
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
    if (column['collation'] == null) {
      return null;
    }

    return ' collate ${wrapValue(column['collation'].toString())}';
  }

  @protected
  String? modifySrid(Blueprint blueprint, Fluent column) {
    return null;
  }

  @protected
  List<String> prefixArray(String prefix, List values) {
    return values.map((value) => '$prefix $value').toList();
  }

  @override
  String wrapTable(dynamic table) {
    if (table is Blueprint) {
      return super.wrapTable(table.getTable());
    }

    return super.wrapTable(table);
  }

  @override
  String wrap(dynamic value, [bool prefixAlias = false]) {
    if (value is Fluent) {
      return super.wrap(value['name'], prefixAlias);
    }

    return super.wrap(value, prefixAlias);
  }

  @override
  String wrapValue(String value) {
    return super.wrapValue(value);
  }

  @protected
  String getDefaultValue(dynamic value) {
    if (value is QueryExpression) {
      return value.getValue().toString();
    }

    if (value is bool) {
      return "'${value ? 1 : 0}'";
    }

    if (value == null) {
      return 'NULL';
    }

    return "'${value.toString().replaceAll("'", "''")}'";
  }

  String compileTableExists() {
    /* ... */ return '';
  }

  String compileColumnExists(String table) {
    /* ... */ return '';
  }

  dynamic getDoctrineTableDiff(Blueprint blueprint, dynamic schema) {
    final tableName = '${getTablePrefix()}${blueprint.getTable()}';

    if (schema is Table) {
      return TableDiff(name: tableName, oldTable: schema);
    }

    if (schema is AbstractSchemaManager) {
      return schema.listTableDetails(tableName).then(
            (table) => TableDiff(name: tableName, oldTable: table),
          );
    }

    throw ArgumentError.value(
        schema, 'schema', 'Expected Table or AbstractSchemaManager.');
  }

  dynamic getRenamedDiff(
      Blueprint blueprint, Fluent command, dynamic column, dynamic schema) {
    if (column is! Column) {
      throw ArgumentError.value(column, 'column', 'Expected Doctrine Column.');
    }

    final tableDiff = getDoctrineTableDiff(blueprint, schema);
    if (tableDiff is Future) {
      return tableDiff.then((diff) => setRenamedColumns(diff, command, column));
    }

    return setRenamedColumns(tableDiff, command, column);
  }

  dynamic setRenamedColumns(dynamic tableDiff, Fluent command, dynamic column) {
    if (tableDiff is! TableDiff) {
      throw ArgumentError.value(tableDiff, 'tableDiff', 'Expected TableDiff.');
    }
    if (column is! Column) {
      throw ArgumentError.value(column, 'column', 'Expected Doctrine Column.');
    }

    final from = command['from'] as String;
    final to = command['to'] as String;
    final renamedColumns = Map<String, String>.from(tableDiff.renamedColumns)
      ..[from.toLowerCase()] = to;

    return TableDiff(
      name: tableDiff.name,
      oldTableName: tableDiff.oldTableName,
      oldTable: tableDiff.oldTable,
      addedColumns: tableDiff.addedColumns,
      changedColumns: tableDiff.changedColumns,
      droppedColumns: tableDiff.droppedColumns,
      renamedColumns: renamedColumns,
      addedIndexes: tableDiff.addedIndexes,
      changedIndexes: tableDiff.changedIndexes,
      droppedIndexes: tableDiff.droppedIndexes,
      renamedIndexes: tableDiff.renamedIndexes,
      addedForeignKeys: tableDiff.addedForeignKeys,
      changedForeignKeys: tableDiff.changedForeignKeys,
      droppedForeignKeys: tableDiff.droppedForeignKeys,
      addedUniqueConstraints: tableDiff.addedUniqueConstraints,
      changedUniqueConstraints: tableDiff.changedUniqueConstraints,
      droppedUniqueConstraints: tableDiff.droppedUniqueConstraints,
    );
  }

  dynamic getChangedDiff(Blueprint blueprint, dynamic schema) {
    if (schema is Table) {
      return Comparator().diffTable(
        schema,
        getTableWithColumnChanges(blueprint, schema),
      );
    }

    if (schema is AbstractSchemaManager) {
      final tableName = '${getTablePrefix()}${blueprint.getTable()}';
      return schema.listTableDetails(tableName).then(
            (table) => Comparator().diffTable(
              table,
              getTableWithColumnChanges(blueprint, table),
            ),
          );
    }

    throw ArgumentError.value(
        schema, 'schema', 'Expected Table or AbstractSchemaManager.');
  }

  List<String> compileTableDiff(TableDiff diff, Blueprint blueprint) {
    if (diff.isEmpty()) {
      return [];
    }

    throw UnsupportedError(
        'TableDiff SQL compilation requires a database-specific grammar.');
  }

  @protected
  String getTableDiffName(TableDiff diff) {
    return diff.oldTable?.getName() ?? diff.name;
  }

  @protected
  String getColumnDeclarationSql(Column column, Blueprint blueprint) {
    final fluent = getFluentForDoctrineColumn(column);
    final type = getType(fluent);
    if (type == null) {
      throw UnsupportedError('Column "${column.getName()}" has no SQL type.');
    }

    return addModifiers('${wrap(column.getName())} $type', blueprint, fluent);
  }

  @protected
  String getColumnTypeDeclarationSql(Column column) {
    final fluent = getFluentForDoctrineColumn(column);
    final type = getType(fluent);
    if (type == null) {
      throw UnsupportedError('Column "${column.getName()}" has no SQL type.');
    }

    return type;
  }

  @protected
  String getCreateIndexSql(Index index, String table) {
    final columns = getIndexColumnsSql(index);

    if (index.isPrimary) {
      return 'alter table $table add primary key ($columns)';
    }

    final unique = index.isUnique ? 'unique ' : '';
    return 'create ${unique}index ${wrap(index.getName())} on $table ($columns)${getPartialIndexSql(index)}';
  }

  @protected
  String getIndexColumnsSql(Index index) {
    return index.getQuotedColumns(this).join(', ');
  }

  @protected
  String getPartialIndexSql(Index index) {
    if (supportsPartialIndexes() && index.hasOption('where')) {
      return ' where ${index.getOption('where')}';
    }

    return '';
  }

  @protected
  bool supportsPartialIndexes() {
    return false;
  }

  @protected
  String getDropIndexSql(Index index, String table) {
    if (index.isPrimary) {
      return 'alter table $table drop primary key';
    }

    return 'drop index ${wrap(index.getName())}';
  }

  @protected
  String getCreateUniqueConstraintSql(
      UniqueConstraint constraint, String table) {
    final columns = constraint.getQuotedColumns(this).join(', ');
    return 'alter table $table add constraint ${wrap(constraint.getName())} unique ($columns)';
  }

  @protected
  String getDropUniqueConstraintSql(UniqueConstraint constraint, String table) {
    return 'alter table $table drop constraint ${wrap(constraint.getName())}';
  }

  @protected
  String getCreateForeignKeySql(ForeignKeyConstraint foreignKey, String table) {
    final localColumns = foreignKey.getQuotedLocalColumns(this).join(', ');
    final foreignTable = foreignKey.getQuotedForeignTableName(this);
    final foreignColumns = foreignKey.getQuotedForeignColumns(this).join(', ');
    var sql =
        'alter table $table add constraint ${wrap(foreignKey.getName())} foreign key ($localColumns) references $foreignTable ($foreignColumns)';

    final onDelete = foreignKey.getOnDelete();
    if (onDelete != null) {
      sql += ' on delete $onDelete';
    }

    final onUpdate = foreignKey.getOnUpdate();
    if (onUpdate != null) {
      sql += ' on update $onUpdate';
    }

    return sql;
  }

  @protected
  String getDropForeignKeySql(ForeignKeyConstraint foreignKey, String table) {
    return 'alter table $table drop foreign key ${wrap(foreignKey.getName())}';
  }

  @protected
  Fluent getFluentForDoctrineColumn(Column column) {
    final attributes = Map<String, dynamic>.from(column.toArray());
    attributes['name'] = column.getName();
    attributes['type'] = getBlueprintColumnType(column.type);
    attributes['nullable'] = !column.notnull;
    attributes['autoIncrement'] = column.autoIncrement;
    attributes['length'] = column.length;
    attributes['total'] = column.precision;
    attributes['places'] = column.scale;
    attributes['default'] = column.defaultValue;
    attributes.removeWhere((_, value) => value == null);
    return Fluent(attributes);
  }

  @protected
  String getBlueprintColumnType(String doctrineType) {
    switch (doctrineType.toLowerCase()) {
      case 'bigint':
        return 'bigInteger';
      case 'smallint':
        return 'smallInteger';
      case 'blob':
        return 'binary';
      case 'varchar':
        return 'string';
      default:
        return doctrineType;
    }
  }

  dynamic getTableWithColumnChanges(Blueprint blueprint, dynamic table) {
    if (table is! Table) {
      throw ArgumentError.value(table, 'table', 'Expected Doctrine Table.');
    }

    final changedTable = table.clone();

    for (final fluent in blueprint.getChangedColumns()) {
      final column = getDoctrineColumnForChange(changedTable, fluent);

      for (final entry in fluent.getAttributes().entries) {
        final option = mapFluentOptionToDoctrine(entry.key.toString());
        if (option != null) {
          column.processOptions({
            option.toString(): mapFluentValueToDoctrine(
              option.toString(),
              entry.value,
            ),
          });
        }
      }
    }

    return changedTable;
  }

  dynamic getDoctrineColumnForChange(dynamic table, Fluent fluent) {
    if (table is! Table) {
      throw ArgumentError.value(table, 'table', 'Expected Doctrine Table.');
    }

    final name = fluent['name'] as String;
    return table
        .changeColumn(name, getDoctrineColumnChangeOptions(fluent))
        .getColumn(name);
  }

  dynamic getDoctrineColumnChangeOptions(Fluent fluent) {
    final type = fluent['type'] as String;
    final options = <String, dynamic>{
      'type': getDoctrineColumnType(type),
    };

    if (['text', 'mediumText', 'longText'].contains(type)) {
      options['length'] = calculateDoctrineTextLength(type);
    } else if (fluent.offsetExists('length')) {
      options['length'] = fluent['length'];
    }

    return options;
  }

  dynamic getDoctrineColumnType(String type) {
    switch (type.toLowerCase()) {
      case 'biginteger':
        return 'bigint';
      case 'smallinteger':
        return 'smallint';
      case 'mediumtext':
      case 'longtext':
        return 'text';
      case 'binary':
        return 'blob';
      default:
        return type.toLowerCase();
    }
  }

  dynamic calculateDoctrineTextLength(String type) {
    switch (type) {
      case 'mediumText':
        return 65535 + 1;
      case 'longText':
        return 16777215 + 1;
      default:
        return 255 + 1;
    }
  }

  dynamic mapFluentOptionToDoctrine(String attribute) {
    switch (attribute) {
      case 'type':
      case 'name':
      case 'change':
        return null;
      case 'nullable':
        return 'notnull';
      case 'total':
        return 'precision';
      case 'places':
        return 'scale';
      default:
        return attribute;
    }
  }

  dynamic mapFluentValueToDoctrine(String option, dynamic value) {
    return option == 'notnull' ? value != true : value;
  }
}
