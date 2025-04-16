// ignore_for_file: unused_import

import 'package:collection/collection.dart'; // Para equality helpers
import 'package:eloquent/eloquent.dart'; // Para SchemaGrammar (pode ser removido se não usar quoting aqui)
import 'package:meta/meta.dart'; // Para @protected

// Importar as outras classes de schema criadas sem prefixo
import 'table.dart';
import 'column.dart';
import 'index.dart';
import 'foreign_key_constraint.dart';
import 'unique_constraint.dart';
import 'column_diff.dart';
import 'schema_config.dart'; // Assumindo que existe
import 'identifier.dart'; // Assumindo que existe

/// Compara duas estruturas de schema (foco em tabelas) para encontrar diferenças.
/// Inspirado em Doctrine\DBAL\Schema\Comparator, mas SIMPLIFICADO.
class Comparator {
  // Removido prefixo 'Dart'

  /// Compara duas tabelas e retorna um TableDiff descrevendo as mudanças.
  TableDiff compareTables(Table oldTable, Table newTable) {
    // Usa Table e TableDiff
    // Mapas para acesso rápido por nome canônico
    final oldColumnMap = {
      for (var c in oldTable.getColumns()) c.getCanonicalName(): c
    };
    final newColumnMap = {
      for (var c in newTable.getColumns()) c.getCanonicalName(): c
    };
    final oldIndexMap = {
      for (var i in oldTable.getIndexes()) i.getCanonicalName(): i
    };
    final newIndexMap = {
      for (var i in newTable.getIndexes()) i.getCanonicalName(): i
    };
    final oldFkMap = {
      for (var fk in oldTable.getForeignKeys()) fk.getCanonicalName(): fk
    };
    final newFkMap = {
      for (var fk in newTable.getForeignKeys()) fk.getCanonicalName(): fk
    };
    final oldUqMap = {
      for (var uq in oldTable.getUniqueConstraints()) uq.getCanonicalName(): uq
    };
    final newUqMap = {
      for (var uq in newTable.getUniqueConstraints()) uq.getCanonicalName(): uq
    };

    // --- Diferenças de Colunas ---
    final addedColumns = <String, Column>{}; // Usa Column
    final changedColumns = <String, ColumnDiff>{}; // Usa ColumnDiff
    final droppedColumns = <String, Column>{}; // Usa Column
    final renamedColumns = <String, String>{}; // Mantém String -> String

    newColumnMap.forEach((name, newColumn) {
      if (!oldColumnMap.containsKey(name)) {
        addedColumns[name] = newColumn;
      } else {
        final oldColumn = oldColumnMap[name]!;
        if (!_columnsEqual(oldColumn, newColumn)) {
          changedColumns[name] =
              ColumnDiff(oldColumn, newColumn); // Usa ColumnDiff
        }
      }
    });

    oldColumnMap.forEach((name, oldColumn) {
      if (!newColumnMap.containsKey(name)) {
        droppedColumns[name] = oldColumn;
      }
    });

    // --- Diferenças de Índices ---
    final addedIndexes = <String, Index>{}; // Usa Index
    final changedIndexes = <String, Index>{}; // Usa Index
    final droppedIndexes = <String, Index>{}; // Usa Index
    final renamedIndexes = <String, String>{}; // Mantém String -> String

    newIndexMap.forEach((name, newIndex) {
      if (!oldIndexMap.containsKey(name)) {
        final oldPk = oldTable.getPrimaryKey();
        if (!(newIndex.isPrimary &&
            oldPk != null &&
            _indexesEqual(oldPk, newIndex))) {
          addedIndexes[name] = newIndex;
        }
      } else {
        final oldIndex = oldIndexMap[name]!;
        if (!_indexesEqual(oldIndex, newIndex)) {
          if (newIndex.isPrimary) {
            changedIndexes[name] = newIndex;
          } else {
            changedIndexes[name] = newIndex;
          }
        }
      }
    });

    oldIndexMap.forEach((name, oldIndex) {
      final newPk = newTable.getPrimaryKey();
      if (!newIndexMap.containsKey(name) &&
          !(oldIndex.isPrimary &&
              newPk != null &&
              _indexesEqual(oldIndex, newPk))) {
        droppedIndexes[name] = oldIndex;
      }
    });

    // --- Diferenças de Chaves Estrangeiras ---
    final addedForeignKeys =
        <String, ForeignKeyConstraint>{}; // Usa ForeignKeyConstraint
    final changedForeignKeys =
        <String, ForeignKeyConstraint>{}; // Usa ForeignKeyConstraint
    final droppedForeignKeys =
        <String, ForeignKeyConstraint>{}; // Usa ForeignKeyConstraint

    newFkMap.forEach((name, newFk) {
      if (!oldFkMap.containsKey(name)) {
        addedForeignKeys[name] = newFk;
      } else {
        if (!_foreignKeysEqual(oldFkMap[name]!, newFk)) {
          changedForeignKeys[name] = newFk;
        }
      }
    });
    oldFkMap.forEach((name, oldFk) {
      if (!newFkMap.containsKey(name)) {
        droppedForeignKeys[name] = oldFk;
      }
    });

    // --- Diferenças de Unique Constraints ---
    final addedUniqueConstraints =
        <String, UniqueConstraint>{}; // Usa UniqueConstraint
    final changedUniqueConstraints =
        <String, UniqueConstraint>{}; // Usa UniqueConstraint
    final droppedUniqueConstraints =
        <String, UniqueConstraint>{}; // Usa UniqueConstraint

    newUqMap.forEach((name, newUq) {
      if (!oldUqMap.containsKey(name)) {
        addedUniqueConstraints[name] = newUq;
      } else {
        if (!oldUqMap[name]!.isEquivalentTo(newUq)) {
          changedUniqueConstraints[name] = newUq;
        }
      }
    });
    oldUqMap.forEach((name, oldUq) {
      if (!newUqMap.containsKey(name)) {
        droppedUniqueConstraints[name] = oldUq;
      }
    });

    return TableDiff(
      // Usa TableDiff
      name: newTable.getName(),
      oldTableName:
          oldTable.getName() != newTable.getName() ? oldTable.getName() : null,
      oldTable: oldTable, // Usa Table
      addedColumns: addedColumns,
      changedColumns: changedColumns,
      droppedColumns: droppedColumns,
      renamedColumns: renamedColumns,
      addedIndexes: addedIndexes,
      changedIndexes: changedIndexes,
      droppedIndexes: droppedIndexes,
      renamedIndexes: renamedIndexes,
      addedForeignKeys: addedForeignKeys,
      changedForeignKeys: changedForeignKeys,
      droppedForeignKeys: droppedForeignKeys,
      addedUniqueConstraints: addedUniqueConstraints,
      changedUniqueConstraints: changedUniqueConstraints,
      droppedUniqueConstraints: droppedUniqueConstraints,
    );
  }

  /// Compara duas colunas (implementação BÁSICA).
  bool _columnsEqual(Column col1, Column col2) {
    // Usa Column
    final col1Props = Map.from(col1.toArray())..remove('name');
    final col2Props = Map.from(col2.toArray())..remove('name');
    return const MapEquality().equals(col1Props, col2Props);
  }

  /// Compara dois índices (implementação BÁSICA).
  bool _indexesEqual(Index idx1, Index idx2) {
    // Usa Index
    return idx1.isFulfilledBy(idx2) && idx2.isFulfilledBy(idx1);
  }

  /// Compara duas chaves estrangeiras (implementação BÁSICA).
  bool _foreignKeysEqual(ForeignKeyConstraint fk1, ForeignKeyConstraint fk2) {
    // Usa ForeignKeyConstraint
    return fk1.isEquivalentTo(fk2);
  }

  /// Compara duas unique constraints (implementação BÁSICA).
  bool uniqueConstraintsEqual(UniqueConstraint uq1, UniqueConstraint uq2) {
    // Usa UniqueConstraint
    return uq1.isEquivalentTo(uq2);
  }
}

// Adicionar as propriedades de Unique Constraint ao TableDiff (se ainda não feito)
// Ajustar o construtor e isEmpty em TableDiff para usar os nomes sem prefixo Dart

class TableDiff {
  final String name;
  final String? oldTableName;
  final Table? oldTable; // Usa Table
  final Map<String, Column> addedColumns; // Usa Column
  final Map<String, ColumnDiff> changedColumns; // Usa ColumnDiff
  final Map<String, Column> droppedColumns; // Usa Column
  final Map<String, String> renamedColumns;
  final Map<String, Index> addedIndexes; // Usa Index
  final Map<String, Index> changedIndexes; // Usa Index
  final Map<String, Index> droppedIndexes; // Usa Index
  final Map<String, String> renamedIndexes;
  final Map<String, ForeignKeyConstraint>
      addedForeignKeys; // Usa ForeignKeyConstraint
  final Map<String, ForeignKeyConstraint>
      changedForeignKeys; // Usa ForeignKeyConstraint
  final Map<String, ForeignKeyConstraint>
      droppedForeignKeys; // Usa ForeignKeyConstraint
  final Map<String, UniqueConstraint>
      addedUniqueConstraints; // Usa UniqueConstraint
  final Map<String, UniqueConstraint>
      changedUniqueConstraints; // Usa UniqueConstraint
  final Map<String, UniqueConstraint>
      droppedUniqueConstraints; // Usa UniqueConstraint

  bool get isRenamed => oldTableName != null && oldTableName != name;

  TableDiff({
    required this.name,
    this.oldTableName,
    this.oldTable, // Usa Table
    this.addedColumns = const {},
    this.changedColumns = const {},
    this.droppedColumns = const {},
    this.renamedColumns = const {},
    this.addedIndexes = const {},
    this.changedIndexes = const {},
    this.droppedIndexes = const {},
    this.renamedIndexes = const {},
    this.addedForeignKeys = const {},
    this.changedForeignKeys = const {},
    this.droppedForeignKeys = const {},
    this.addedUniqueConstraints = const {},
    this.changedUniqueConstraints = const {},
    this.droppedUniqueConstraints = const {},
  });

  bool isEmpty() {
    return addedColumns.isEmpty &&
        changedColumns.isEmpty &&
        droppedColumns.isEmpty &&
        renamedColumns.isEmpty &&
        addedIndexes.isEmpty &&
        changedIndexes.isEmpty &&
        droppedIndexes.isEmpty &&
        renamedIndexes.isEmpty &&
        addedForeignKeys.isEmpty &&
        changedForeignKeys.isEmpty &&
        droppedForeignKeys.isEmpty &&
        addedUniqueConstraints.isEmpty &&
        changedUniqueConstraints.isEmpty &&
        droppedUniqueConstraints.isEmpty &&
        !isRenamed;
  }
}
