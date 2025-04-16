import 'column.dart';

/// Representa as diferenças entre duas definições de coluna.
/// Inspirado em Doctrine\DBAL\Schema\ColumnDiff.
class ColumnDiff {
  Column oldColumn;
  Column newColumn;

  /// Lista de propriedades que mudaram (para informação).
  List<String> changedProperties = [];

  ColumnDiff(this.oldColumn, this.newColumn) {
    _findChangedProperties();
  }

  /// Método auxiliar para popular changedProperties (simplificado).
  void _findChangedProperties() {
    if (oldColumn.getName() != newColumn.getName())
      changedProperties.add('name');
    if (oldColumn.type != newColumn.type) changedProperties.add('type');
    if (oldColumn.length != newColumn.length) changedProperties.add('length');
    if (oldColumn.precision != newColumn.precision)
      changedProperties.add('precision');
    if (oldColumn.scale != newColumn.scale) changedProperties.add('scale');
    if (oldColumn.unsigned != newColumn.unsigned)
      changedProperties.add('unsigned');
    if (oldColumn.fixed != newColumn.fixed) changedProperties.add('fixed');
    if (oldColumn.notnull != newColumn.notnull)
      changedProperties.add('notnull');
    if (oldColumn.defaultValue != newColumn.defaultValue)
      changedProperties.add('default');
    if (oldColumn.autoIncrement != newColumn.autoIncrement)
      changedProperties.add('autoincrement');
    if (oldColumn.comment != newColumn.comment)
      changedProperties.add('comment');
    if (oldColumn.collation != newColumn.collation)
      changedProperties.add('collation');
    // TODO: Comparar platformOptions de forma mais robusta
    if (oldColumn.platformOptions.toString() !=
        newColumn.platformOptions.toString()) {
      changedProperties.add('platformOptions');
    }
    if (oldColumn.columnDefinition != newColumn.columnDefinition)
      changedProperties.add('columnDefinition');
  }

  bool hasChanged(String propertyName) {
    return changedProperties.contains(propertyName.toLowerCase());
  }

  bool hasNameChanged() => hasChanged('name');
  bool hasTypeChanged() => hasChanged('type');
  bool hasLengthChanged() => hasChanged('length');
  bool hasPrecisionChanged() => hasChanged('precision');
  bool hasScaleChanged() => hasChanged('scale');
  bool hasUnsignedChanged() => hasChanged('unsigned');
  bool hasFixedChanged() => hasChanged('fixed');
  bool hasNotNullChanged() => hasChanged('notnull');
  bool hasDefaultChanged() => hasChanged('default');
  bool hasAutoIncrementChanged() => hasChanged('autoincrement');
  bool hasCommentChanged() => hasChanged('comment');
  bool hasCollationChanged() => hasChanged('collation');
  // ... outros métodos has...Changed()
}
