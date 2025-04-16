// File: C:\MyDartProjects\eloquent\lib\src\doctrine\schema_diff.dart

import 'table.dart';
import 'table_diff.dart';
import 'sequence.dart';

/// Represents the differences found between two database schemas.
/// Corresponds to Doctrine\DBAL\Schema\SchemaDiff.
class SchemaDiff {
  /// List of names of schemas that were created.
  final List<String> createdSchemas;

  /// List of names of schemas that were dropped.
  final List<String> droppedSchemas;

  /// List of tables that were created.
  final List<Table> createdTables;

  /// List of table differences for tables that were altered.
  /// Only includes diffs that actually contain changes (are not empty).
  final List<TableDiff> alteredTables;

  /// List of tables that were dropped.
  final List<Table> droppedTables;

  /// List of sequences that were created.
  final List<Sequence> createdSequences;

  /// List of sequences that were altered.
  /// Note: Doctrine's SchemaDiff doesn't explicitly store the "before" state
  /// for altered sequences, just the new state. The platform typically needs
  /// only the new state to generate ALTER SEQUENCE SQL.
  final List<Sequence> alteredSequences;

  /// List of sequences that were dropped.
  final List<Sequence> droppedSequences;

  /// Constructs a SchemaDiff object.
  ///
  /// Typically instantiated by a Comparator.
  ///
  /// [createdSchemas] - Names of schemas to be created.
  /// [droppedSchemas] - Names of schemas to be dropped.
  /// [createdTables] - Table objects to be created.
  /// [alteredTablesInput] - List of TableDiff objects representing changes.
  ///                        Empty diffs will be filtered out.
  /// [droppedTables] - Table objects to be dropped.
  /// [createdSequences] - Sequence objects to be created.
  /// [alteredSequences] - Sequence objects representing the altered state.
  /// [droppedSequences] - Sequence objects to be dropped.
  SchemaDiff({
    this.createdSchemas = const [],
    this.droppedSchemas = const [],
    this.createdTables = const [],
    List<TableDiff> alteredTablesInput =
        const [], // Use different name for input
    this.droppedTables = const [],
    this.createdSequences = const [],
    this.alteredSequences = const [],
    this.droppedSequences = const [],
  }) : // Filter out empty TableDiffs during initialization
        alteredTables =
            alteredTablesInput.where((diff) => !diff.isEmpty()).toList();

  // --- Getters for accessing the differences ---

  /// Returns the list of names for schemas to be created.
  List<String> getCreatedSchemas() {
    return List.unmodifiable(createdSchemas);
  }

  /// Returns the list of names for schemas to be dropped.
  List<String> getDroppedSchemas() {
    return List.unmodifiable(droppedSchemas);
  }

  /// Returns the list of Table objects to be created.
  List<Table> getCreatedTables() {
    return List.unmodifiable(createdTables);
  }

  /// Returns the list of TableDiff objects for altered tables.
  List<TableDiff> getAlteredTables() {
    return List.unmodifiable(alteredTables);
  }

  /// Returns the list of Table objects to be dropped.
  List<Table> getDroppedTables() {
    return List.unmodifiable(droppedTables);
  }

  /// Returns the list of Sequence objects to be created.
  List<Sequence> getCreatedSequences() {
    return List.unmodifiable(createdSequences);
  }

  /// Returns the list of altered Sequence objects (representing the target state).
  List<Sequence> getAlteredSequences() {
    return List.unmodifiable(alteredSequences);
  }

  /// Returns the list of Sequence objects to be dropped.
  List<Sequence> getDroppedSequences() {
    return List.unmodifiable(droppedSequences);
  }

  /// Returns whether the diff is empty (contains no changes).
  bool isEmpty() {
    return createdSchemas.isEmpty &&
        droppedSchemas.isEmpty &&
        createdTables.isEmpty &&
        alteredTables.isEmpty && // Already filtered for non-empty diffs
        droppedTables.isEmpty &&
        createdSequences.isEmpty &&
        alteredSequences.isEmpty &&
        droppedSequences.isEmpty;
  }
}
