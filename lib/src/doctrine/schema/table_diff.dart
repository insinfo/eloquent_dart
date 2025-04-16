import 'table.dart';
import 'column.dart';
import 'index.dart';
import 'foreign_key_constraint.dart';
import 'column_diff.dart';

/// Representa as diferenças entre duas definições de tabela.
/// Inspirado em Doctrine\DBAL\Schema\TableDiff.
class TableDiff {
  /// Nome da tabela (pode ser o antigo ou novo se renomeado).
  final String name;

  /// Nome antigo da tabela, se foi renomeada.
  final String? oldTableName;

  /// Tabela original (estado "from"). Pode ser null se for uma tabela nova.
  final Table? oldTable;

  /// Colunas adicionadas (nome canônico -> DartColumn).
  final Map<String, Column> addedColumns;

  /// Colunas alteradas (nome canônico antigo -> DartColumnDiff).
  final Map<String, ColumnDiff> changedColumns;

  /// Colunas removidas (nome canônico -> DartColumn).
  final Map<String, Column> droppedColumns;

  /// Colunas renomeadas (nome canônico antigo -> nome canônico novo).
  final Map<String, String> renamedColumns;

  /// Índices adicionados (nome canônico -> DartIndex).
  final Map<String, Index> addedIndexes;

  /// Índices alterados (nome canônico -> DartIndex - representa o *novo* estado).
  final Map<String, Index> changedIndexes;

  /// Índices removidos (nome canônico -> DartIndex).
  final Map<String, Index> droppedIndexes;

  /// Índices renomeados (nome canônico antigo -> nome canônico novo).
  final Map<String, String> renamedIndexes;

  /// Chaves estrangeiras adicionadas (nome canônico -> DartForeignKeyConstraint).
  final Map<String, ForeignKeyConstraint> addedForeignKeys;

  /// Chaves estrangeiras alteradas (nome canônico -> DartForeignKeyConstraint - representa o *novo* estado).
  final Map<String, ForeignKeyConstraint> changedForeignKeys;

  /// Chaves estrangeiras removidas (nome canônico -> DartForeignKeyConstraint).
  final Map<String, ForeignKeyConstraint> droppedForeignKeys;

  /// Indica se a tabela foi renomeada.
  bool get isRenamed => oldTableName != null && oldTableName != name;

  TableDiff({
    required this.name, // Nome atual/novo da tabela
    this.oldTableName,
    this.oldTable,
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
  });

  /// Verifica se existem diferenças registradas.
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
        !isRenamed; // Considera renomeação de tabela como uma diferença
  }
}
