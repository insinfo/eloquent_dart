import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  test('renameColumn updates indexes, unique constraints and foreign keys', () {
    final table = Table('pedido');
    table.addColumn('id', 'integer');
    table.addColumn('cliente_id', 'integer');
    table.addColumn('codigo', 'string');
    table.addIndex(columns: ['cliente_id', 'id'], name: 'idx_cliente');
    table.addUniqueConstraint(columns: ['codigo'], name: 'uniq_codigo');
    table.addForeignKey(
        localColumns: ['cliente_id'],
        foreignTableName: 'cliente',
        foreignColumns: ['id'],
        name: 'fk_cliente');

    table.renameColumn('cliente_id', 'id_cliente');
    table.renameColumn('codigo', 'Codigo_Pedido');

    expect(table.getIndex('idx_cliente').getColumns(), ['id_cliente', 'id']);
    expect(table.getUniqueConstraint('uniq_codigo').getColumns(),
        ['Codigo_Pedido']);
    expect(table.getForeignKey('fk_cliente').getLocalColumns(), ['id_cliente']);
    expect(table.getForeignKey('fk_cliente').getForeignColumns(), ['id']);
  });
}
