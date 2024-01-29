//import 'dart:io';
import 'package:eloquent/eloquent.dart';

Future<Connection> getConn() async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3',
    'host': 'localhost',
    'port': '5435',
    'database': 'cracha',
    'username': 'sisadmin',
    'password': 's1sadm1n',
    'charset': 'utf8',
    'prefix': '',
    'schema': ['public'],
    //'sslmode' : 'require',
    // 'pool': true,
    // 'poolsize': 50,
  });
  manager.setAsGlobal();
  final db = await manager.connection();
  return db;
}

var data = {
  'numero': -1,
  'nome': '123',
  'sexo': '',
  'logradouro': '123',
  'rua': '123',
  'numero_casa': 123,
  'complemento': '',
  'cidade': 'cidade',
  'bairro': 'bairro',
  'estado': 'RJ',
  'pais': 'pais',
  'cep': '123',
  'ddd': 'ddd',
  'telefone1': 'telefone1',
  'telefone2': 'telefone2',
  'fax': 'fax',
  'celular': 'celular',
  'email': 'email',
  'observacao': 'observacao',
  'dtnascimento': DateTime.now(),
  'dtcadastro': DateTime.now(),
  'matricula': '123',
  'dtadesao': DateTime.now(),
  'campo1': 'campo1',
  'campo2': 'campo2',
  'campo3': 'campo3',
  'campo4': 'campo4',
  'campo5': '13128250731',
  'campo6': 'campo6',
  'campo7': 'campo7',
  'campo8': 'campo8',
  'campo9': 'campo9',
  'campo10': 'campo10',
  'campo11': 'campo11',
  'campo12': 'campo12',
};
void main(List<String> args) async {
  final db = await getConn();

  final id = await db.transaction((ctx) async {
    final lastCod = await ctx
        .table('public.clientes')
        .selectRaw('MAX(numero) AS cod')
        .first();

    final nextCod = lastCod == null || lastCod['cod'] == null
        ? 1
        : (lastCod['cod'] as int) + 1;

    final query = ctx.table('public.clientes');

    data['numero'] = nextCod;

    final numero = await query.insertGetId(data, 'numero');

    return numero;
  });

  print('insertGetId: $id');
}
