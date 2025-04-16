// ignore_for_file: unused_local_variable

import 'dart:collection';
import 'dart:math';
import 'package:meta/meta.dart'; // Para @protected

import 'abstract_asset.dart';
import 'column.dart'; // Agora se chama Column
import 'index.dart'; // Agora se chama Index
import 'foreign_key_constraint.dart'; // Agora se chama ForeignKeyConstraint
import 'unique_constraint.dart'; // Agora se chama UniqueConstraint

import 'schema_config.dart';

/// Representa uma tabela de banco de dados em memória, aprimorada.
/// Mais alinhado com Doctrine\DBAL\Schema\Table.
class Table extends AbstractAsset {
  // Removido o prefixo 'Dart'

  /// Colunas da tabela (nome canônico -> Column).
  final Map<String, Column> _columns = LinkedHashMap();

  /// Índices da tabela (nome canônico -> Index), inclui implícitos.
  final Map<String, Index> _indexes = LinkedHashMap();

  /// Índices criados implicitamente por constraints (nome canônico -> Index).
  final Map<String, Index> _implicitIndexes = LinkedHashMap();

  /// Constraints de unicidade (nome canônico -> UniqueConstraint).
  final Map<String, UniqueConstraint> _uniqueConstraints = LinkedHashMap();

  /// Chaves estrangeiras (nome canônico -> ForeignKeyConstraint).
  final Map<String, ForeignKeyConstraint> _foreignKeys = LinkedHashMap();

  /// Nome canônico do índice da chave primária, se houver.
  String? _primaryKeyName;

  /// Opções da tabela (ex: comment). Chaves em lowercase.
  final Map<String, dynamic> _options;

  /// Configuração do Schema (para max identifier length, etc.).
  SchemaConfig? _schemaConfig;

  /// Rastreia colunas renomeadas (nome canônico ANTIGO -> nome canônico NOVO).
  final Map<String, String> renamedColumns = {};

  /// Rastreia índices renomeados (nome canônico ANTIGO -> nome canônico NOVO).
  final Map<String, String> renamedIndexes = {};

  /// Construtor principal.
  Table(
    String name, {
    List<Column> columns = const [],
    List<Index> indexes = const [],
    List<UniqueConstraint> uniqueConstraints = const [],
    List<ForeignKeyConstraint> foreignKeys = const [],
    Map<String, dynamic> options = const {},
    SchemaConfig? schemaConfig,
  }) : _options = Map.fromEntries(options.entries
            .map((e) => MapEntry(e.key.toLowerCase(), e.value))) {
    if (name.trim().isEmpty) {
      throw Exception('Invalid table name: "$name"');
    }
    setName(name); // Usar _setName da classe base
    _schemaConfig = schemaConfig;

    columns.forEach(_addColumnInternal);
    indexes.forEach(_addIndexInternal);
    uniqueConstraints.forEach(_addUniqueConstraintInternal);
    foreignKeys.forEach(_addForeignKeyInternal);

    if (_schemaConfig != null) {
      _schemaConfig!.getDefaultTableOptions().forEach((key, value) {
        _options.putIfAbsent(key.toLowerCase(), () => value);
      });
    }
  }

  /// Define a configuração do Schema para esta tabela.
  void setSchemaConfig(SchemaConfig schemaConfig) {
    _schemaConfig = schemaConfig;
  }

  // --- Normalização e Validação Interna ---
  @protected
  String normalizeIdentifier(String identifier) {
    return trimQuotes(identifier).toLowerCase();
  }

  @protected
  void _validateIdentifierName(String name) {
    final cleanName = trimQuotes(name);
    if (cleanName.isEmpty) throw Exception('Identifier name cannot be empty.');
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(cleanName) &&
        !isIdentifierQuoted(name)) {
      print(
          "Warning: Identifier name '$name' might contain invalid characters or reserved words.");
    }
    if (name.length > _getMaxIdentifierLength()) {
      print(
          "Warning: Identifier name '$name' exceeds maximum length of ${_getMaxIdentifierLength()}.");
    }
  }

  @protected
  void _validateColumnsExist(List<String> columnNames, String contextName) {
    for (final columnName in columnNames) {
      if (!hasColumn(columnName)) {
        throw Exception(
            'Column "$columnName" does not exist in table "${getName()}" for $contextName.');
      }
    }
  }

  // --- Manipulação de Colunas ---
  Column addColumn(String name, String typeName,
      {Map<String, dynamic> options = const {}}) {
    _validateIdentifierName(name);
    final column =
        Column(name, typeName, options: options); // Usa Column sem prefixo
    _addColumnInternal(column);
    return column;
  }

  @protected
  void _addColumnInternal(Column column) {
    // Usa Column sem prefixo
    final name = column.getCanonicalName();
    if (_columns.containsKey(name))
      throw Exception('Column "$name" already exists.');
    _columns[name] = column;
  }

  void dropColumn(String columnName) {
    final nameCanonical = normalizeIdentifier(columnName);
    getColumn(nameCanonical); // Valida existência

    final indexesToRemove = <String>[];
    _indexes.forEach((indexName, index) {
      if (index.getUnquotedColumns().contains(nameCanonical))
        indexesToRemove.add(indexName);
    });
    indexesToRemove.forEach((indexName) {
      print("Warning: Dropping index '$indexName'.");
      dropIndex(indexName);
    });

    final fksToRemove = <String>[];
    _foreignKeys.forEach((fkName, fk) {
      if (fk.getUnquotedLocalColumns().contains(nameCanonical))
        fksToRemove.add(fkName);
    });
    fksToRemove.forEach((fkName) {
      print("Warning: Dropping foreign key '$fkName'.");
      removeForeignKey(fkName);
    });

    final uqsToRemove = <String>[];
    _uniqueConstraints.forEach((uqName, uq) {
      if (uq.getUnquotedColumns().contains(nameCanonical))
        uqsToRemove.add(uqName);
    });
    uqsToRemove.forEach((uqName) {
      print("Warning: Dropping unique constraint '$uqName'.");
      removeUniqueConstraint(uqName);
    });

    _columns.remove(nameCanonical);
  }

  Column modifyColumn(String columnName, Map<String, dynamic> changes) {
    final column = getColumn(columnName);
    column.processOptions(changes); // Assumindo que Column tem processOptions
    if (changes.containsKey('autoIncrement') && column.isAutoIncrement) {
      column.notnull = true;
    }
    return column;
  }

  Column renameColumn(String oldColumnName, String newColumnName) {
    final oldNameCanonical = normalizeIdentifier(oldColumnName);
    final newNameCanonical = normalizeIdentifier(newColumnName);
    final column = getColumn(oldNameCanonical);

    if (oldNameCanonical == newNameCanonical) return column;
    if (hasColumn(newNameCanonical))
      throw Exception('Column "$newColumnName" already exists.');

    _validateIdentifierName(newColumnName);

    _columns.remove(oldNameCanonical);
    column.setName(newColumnName); // Assumindo que Column tem setName
    _columns[newNameCanonical] = column;

    String originalOldName = oldNameCanonical;
    if (renamedColumns.containsKey(oldNameCanonical)) {
      originalOldName = renamedColumns.remove(oldNameCanonical)!;
    }
    renamedColumns[originalOldName] = newNameCanonical;

    _updateColumnInIndexesAndFKs(oldNameCanonical, newNameCanonical);

    return column;
  }

  // --- Getters e Has de Colunas ---
  bool hasColumn(String columnName) =>
      _columns.containsKey(normalizeIdentifier(columnName));
  Column getColumn(String columnName) {
    final name = normalizeIdentifier(columnName);
    if (!hasColumn(name)) throw Exception('Column "$name" does not exist.');
    return _columns[name]!;
  }

  List<Column> getColumns() => List.unmodifiable(_columns.values);
  Map<String, String> getRenamedColumns() => Map.unmodifiable(renamedColumns);

  // --- Manipulação de Índices ---
  Index addIndex(
      {required List<String> columns,
      String? name,
      List<String> flags = const [],
      Map<String, dynamic> options = const {}}) {
    name ??= _generateIdentifierName(columns, 'idx');
    final index = _createIndex(columns, name, false, false, flags, options);
    _addIndexInternal(index);
    return index;
  }

  Index addUniqueIndex(
      {required List<String> columns,
      String? name,
      Map<String, dynamic> options = const {}}) {
    name ??= _generateIdentifierName(columns, 'uniq');
    final index = _createIndex(columns, name, true, false, [], options);
    _addIndexInternal(index);
    return index;
  }

  Index setPrimaryKey(List<String> columnNames, [String? name]) {
    name ??= _generateIdentifierName([], 'primary');
    if (_primaryKeyName != null &&
        normalizeIdentifier(name) != _primaryKeyName) {
      dropPrimaryKey();
    } else if (_primaryKeyName != null) {
      dropPrimaryKey();
    }
    final index = _createIndex(columnNames, name, true, true);
    _addIndexInternal(index);

    for (final colName in columnNames) {
      getColumn(colName).notnull = true;
    }
    return index;
  }

  @protected
  void _addIndexInternal(Index indexCandidate) {
    final indexName = indexCandidate.getCanonicalName();
    _validateIdentifierName(indexCandidate.getName());
    final replacedImplicitIndexes = <String>{};

    _implicitIndexes.forEach((name, implicitIndex) {
      if (implicitIndex.isFulfilledBy(indexCandidate) &&
          _indexes.containsKey(name)) {
        replacedImplicitIndexes.add(name);
      }
    });

    final alreadyExistsExplicitly = _indexes.containsKey(indexName) &&
        !replacedImplicitIndexes.contains(indexName);
    final conflictingPrimaryKey = _primaryKeyName != null &&
        indexCandidate.isPrimary &&
        _primaryKeyName != indexName;

    if (alreadyExistsExplicitly || conflictingPrimaryKey) {
      throw Exception(
          'Index "$indexName" already exists or primary key conflict.');
    }

    replacedImplicitIndexes.forEach((name) {
      _indexes.remove(name);
      _implicitIndexes.remove(name);
    });

    if (indexCandidate.isPrimary) _primaryKeyName = indexName;
    _indexes[indexName] = indexCandidate;
  }

  void dropIndex(String indexName) {
    final name = normalizeIdentifier(indexName);
    if (!hasIndex(name)) throw Exception('Index "$name" does not exist.');
    if (_primaryKeyName == name) _primaryKeyName = null;
    _indexes.remove(name);
    _implicitIndexes.remove(name);
  }

  void dropPrimaryKey() {
    if (_primaryKeyName != null) dropIndex(_primaryKeyName!);
  }

  Index renameIndex(String oldIndexName, String newIndexName) {
    final oldNameCanonical = normalizeIdentifier(oldIndexName);
    final index = getIndex(oldNameCanonical);
    final newNameCanonical = normalizeIdentifier(newIndexName);
    if (oldNameCanonical == newNameCanonical) return index;
    if (hasIndex(newNameCanonical))
      throw Exception('Index "$newIndexName" already exists.');
    _validateIdentifierName(newIndexName);
    dropIndex(oldNameCanonical);
    final newIndex = Index(
        name: newIndexName,
        columns: index.getColumns(),
        isPrimary: index.isPrimary,
        isUnique: index.isUnique,
        flags: index.getFlags(),
        options: index.getOptions());
    _addIndexInternal(newIndex);
    String originalOldName = oldNameCanonical;
    if (renamedIndexes.containsKey(oldNameCanonical)) {
      originalOldName = renamedIndexes.remove(oldNameCanonical)!;
    }
    renamedIndexes[originalOldName] = newNameCanonical;
    return newIndex;
  }

  // --- Getters e Has de Índices ---
  bool hasIndex(String indexName) =>
      _indexes.containsKey(normalizeIdentifier(indexName));
  Index getIndex(String indexName) {
    final name = normalizeIdentifier(indexName);
    if (!hasIndex(name)) throw Exception('Index "$name" does not exist.');
    return _indexes[name]!;
  }

  List<Index> getIndexes() => List.unmodifiable(_indexes.values);
  Index? getPrimaryKey() =>
      _primaryKeyName != null ? _indexes[_primaryKeyName!] : null;

  // --- Manipulação de Unique Constraints ---
  UniqueConstraint addUniqueConstraint(
      {required List<String> columns,
      String? name,
      List<String> flags = const [],
      Map<String, dynamic> options = const {}}) {
    name ??= _generateIdentifierName(columns, 'uniq');
    final constraint = _createUniqueConstraint(columns, name, flags, options);
    _addUniqueConstraintInternal(constraint);
    return constraint;
  }

  @protected
  void _addUniqueConstraintInternal(UniqueConstraint constraint) {
    final name = constraint.getCanonicalName();
    _validateIdentifierName(constraint.getName());
    if (_uniqueConstraints.containsKey(name))
      throw Exception('Unique constraint "$name" already exists.');
    _uniqueConstraints[name] = constraint;
    _ensureConstraintIndex(constraint, isUnique: true);
  }

  void removeUniqueConstraint(String constraintName) {
    final name = normalizeIdentifier(constraintName);
    if (!hasUniqueConstraint(name))
      throw Exception('Unique constraint "$name" does not exist.');
    _uniqueConstraints.remove(name);
  }

  // --- Getters e Has de Unique Constraints ---
  bool hasUniqueConstraint(String name) =>
      _uniqueConstraints.containsKey(normalizeIdentifier(name));
  UniqueConstraint getUniqueConstraint(String name) {
    final canonicalName = normalizeIdentifier(name);
    if (!hasUniqueConstraint(canonicalName))
      throw Exception('Unique constraint "$name" does not exist.');
    return _uniqueConstraints[canonicalName]!;
  }

  List<UniqueConstraint> getUniqueConstraints() =>
      List.unmodifiable(_uniqueConstraints.values);

  // --- Manipulação de Chaves Estrangeiras ---
  ForeignKeyConstraint addForeignKey(
      {required List<String> localColumns,
      required String foreignTableName,
      required List<String> foreignColumns,
      String? name,
      Map<String, dynamic> options = const {}}) {
    name ??= _generateIdentifierName(localColumns, 'fk');
    final fk = _createForeignKeyConstraint(
        localColumns, foreignTableName, foreignColumns, name, options);
    _addForeignKeyInternal(fk);
    return fk;
  }

  @protected
  void _addForeignKeyInternal(ForeignKeyConstraint fk) {
    final name = fk.getCanonicalName();
    _validateIdentifierName(fk.getName());
    if (_foreignKeys.containsKey(name))
      throw Exception('Foreign key "$name" already exists.');
    _validateColumnsExist(
        fk.getLocalColumns(), 'foreign key "$name"'); // Valida colunas locais
    _foreignKeys[name] = fk;
    _ensureConstraintIndex(fk, isUnique: false);
  }

  @protected
  void _ensureConstraintIndex(dynamic constraint, {required bool isUnique}) {
    final List<String> columns = constraint.getColumns();
    bool indexExists = _indexes.values.any((index) =>
        (isUnique ? index.isUnique : true) && index.spansColumns(columns));

    if (!indexExists) {
      final indexName = _generateIdentifierName(columns, 'idx');
      final implicitIndexName = normalizeIdentifier(indexName);
      if (!_indexes.containsKey(implicitIndexName)) {
        print(
            "Info: Adding implicit ${isUnique ? 'unique ' : ''}index '$indexName' for constraint '${constraint.getName()}'.");
        final indexCandidate =
            _createIndex(columns, indexName, isUnique, false);
        _addIndexInternal(indexCandidate);
        _implicitIndexes[implicitIndexName] = indexCandidate;
      }
    }
  }

  void removeForeignKey(String fkName) {
    final name = normalizeIdentifier(fkName);
    if (!hasForeignKey(name))
      throw Exception('Foreign key "$name" does not exist.');
    _foreignKeys.remove(name);
  }

  // --- Getters e Has de Chaves Estrangeiras ---
  bool hasForeignKey(String fkName) =>
      _foreignKeys.containsKey(normalizeIdentifier(fkName));
  ForeignKeyConstraint getForeignKey(String fkName) {
    final name = normalizeIdentifier(fkName);
    if (!hasForeignKey(name))
      throw Exception('Foreign key "$name" does not exist.');
    return _foreignKeys[name]!;
  }

  List<ForeignKeyConstraint> getForeignKeys() =>
      List.unmodifiable(_foreignKeys.values);

  // --- Manipulação de Opções ---
  void addOption(String name, dynamic value) =>
      _options[name.toLowerCase()] = value;
  dynamic getOption(String name) => _options[name.toLowerCase()];
  bool hasOption(String name) => _options.containsKey(name.toLowerCase());
  Map<String, dynamic> getOptions() => Map.unmodifiable(_options);
  void setComment(String comment) => addOption('comment', comment);
  String? getComment() => getOption('comment') as String?;

  // --- Métodos Auxiliares ---
  bool columnsAreIndexed(List<String> columnNames) =>
      getIndexes().any((index) => index.spansColumns(columnNames));
  int _getMaxIdentifierLength() =>
      _schemaConfig?.getMaxIdentifierLength() ?? 63;

  @protected
  String _generateIdentifierName(List<String> columnNames, String prefix,
      [int? maxLength]) {
    maxLength ??= _getMaxIdentifierLength();
    final cleanColumns =
        columnNames.map((c) => trimQuotes(c.split('.').last)).toList();
    String namePart = '${getName()}_${cleanColumns.join('_')}';
    String hashData = '$namePart.$prefix';
    String shortHash = hashData.hashCode
        .abs()
        .toRadixString(36)
        .substring(0, min(hashData.hashCode.abs().toRadixString(36).length, 8));
    String baseName = '${prefix}_${namePart}_$shortHash'.toLowerCase();
    baseName = baseName
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (baseName.length > maxLength) {
      int maxBaseLen = maxLength - prefix.length - shortHash.length - 2;
      if (maxBaseLen < 5) maxBaseLen = 5;
      String truncatedNamePart = getName().length > maxBaseLen
          ? getName().substring(0, maxBaseLen)
          : getName();
      baseName = '${prefix}_${truncatedNamePart}_$shortHash';
      if (baseName.length > maxLength) {
        baseName = baseName.substring(0, maxLength);
      }
    }
    return baseName;
  }

  @protected
  Index _createIndex(
      List<String> columns, String indexName, bool isUnique, bool isPrimary,
      [List<String> flags = const [],
      Map<String, dynamic> options = const {}]) {
    _validateIdentifierName(indexName);
    _validateColumnsExist(columns, 'index "$indexName"');
    return Index(
        name: indexName,
        columns: columns,
        isUnique: isUnique,
        isPrimary: isPrimary,
        flags: flags,
        options: options);
  }

  @protected
  UniqueConstraint _createUniqueConstraint(
      List<String> columns, String constraintName,
      [List<String> flags = const [],
      Map<String, dynamic> options = const {}]) {
    _validateIdentifierName(constraintName);
    _validateColumnsExist(columns, 'unique constraint "$constraintName"');
    return UniqueConstraint(
        name: constraintName, columns: columns, flags: flags, options: options);
  }

  @protected
  ForeignKeyConstraint _createForeignKeyConstraint(
      List<String> localColumns,
      String foreignTableName,
      List<String> foreignColumns,
      String constraintName,
      [Map<String, dynamic> options = const {}]) {
    _validateIdentifierName(constraintName);
    _validateColumnsExist(
        localColumns, 'foreign key constraint "$constraintName"');
    return ForeignKeyConstraint(
        name: constraintName,
        localColumns: localColumns,
        foreignTableName: foreignTableName,
        foreignColumns: foreignColumns,
        options: options);
  }

  void _updateColumnInIndexesAndFKs(
      String oldNameCanonical, String newNameCanonical) {
    final originalNewName = _columns[newNameCanonical]!.getOriginalName();

    // Atualiza Índices
    _indexes.values.forEach((index) {
      //bool changed = false;
      // final newColumns = index.getColumns().map((col) {
      //   if (normalizeIdentifier(col) == oldNameCanonical) {
      //     changed = true;
      //     return originalNewName;
      //   }
      //   return col;
      // }).toList();
      // if (changed) {
      //   // Não podemos modificar _columns diretamente se for final e imutável em DartIndex
      //   // Precisaríamos recriar o índice ou tornar _columns mutável em DartIndex
      //   print(
      //       "Error/TODO: Cannot update columns in immutable Index object '${index.getName()}'. Needs recreation or mutable Index._columns.");
      //   // Exemplo (se _columns fosse mutável): index._columns = List.unmodifiable(newColumns);
      // }
    });
    // Atualiza Unique Constraints
    _uniqueConstraints.values.forEach((uc) {
      //bool changed = false;
      // final newColumns = uc.getColumns().map((col) {
      //   if (normalizeIdentifier(col) == oldNameCanonical) {
      //     changed = true;
      //     return originalNewName;
      //   }
      //   return col;
      // }).toList();
      // if (changed) {
      //   // Mesmo problema de imutabilidade que DartIndex
      //   print(
      //       "Error/TODO: Cannot update columns in immutable UniqueConstraint object '${uc.getName()}'.");
      //   // Exemplo (se _columns fosse mutável): uc._columns = LinkedHashMap.fromEntries(newColumns.map((c) => MapEntry(c, Identifier(c))));
      // }
    });
    // Atualiza Chaves Estrangeiras (Locais)
    _foreignKeys.values.forEach((fk) {
      bool changed = false;
      final newLocalColumns = fk.getLocalColumns().map((col) {
        if (normalizeIdentifier(col) == oldNameCanonical) {
          changed = true;
          return originalNewName;
        }
        return col;
      }).toList();
      if (changed) {
        // Mesmo problema de imutabilidade
        print(
            "Error/TODO: Cannot update columns in immutable ForeignKeyConstraint object '${fk.getName()}'.");
        // Exemplo (se _localColumnNames fosse mutável): fk._localColumnNames = LinkedHashMap.fromEntries(newLocalColumns.map((c) => MapEntry(c, Identifier(c))));
      }
    });
  }

  /// Cria uma cópia profunda desta tabela e seus assets.
  Table clone() {
    final clonedColumns = _columns.values.map((c) => c.clone()).toList();
    final clonedIndexes = _indexes.values.map((i) => i.clone()).toList();
    final clonedUniqueConstraints =
        _uniqueConstraints.values.map((u) => u.clone()).toList();
    final clonedForeignKeys =
        _foreignKeys.values.map((f) => f.clone()).toList();

    final clonedTable = Table(
      name, // Usa o nome original armazenado pela classe base
      columns: clonedColumns,
      // Não passa indexes/unique/fk aqui, adiciona via métodos internos para tratar implícitos
      options: Map.from(_options),
      schemaConfig: _schemaConfig,
    );

    // Adiciona indexes, uqs, fks copiados usando a lógica interna
    clonedIndexes.forEach(clonedTable._addIndexInternal);
    clonedUniqueConstraints.forEach(clonedTable._addUniqueConstraintInternal);
    clonedForeignKeys.forEach(clonedTable._addForeignKeyInternal);

    // Copia o estado de renomeação
    clonedTable.renamedColumns.addAll(renamedColumns);
    clonedTable.renamedIndexes.addAll(renamedIndexes);
    // _implicitIndexes e _primaryKeyName serão reconstruídos ao adicionar os itens

    return clonedTable;
  }
}
