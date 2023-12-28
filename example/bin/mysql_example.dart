import 'dart:io';
import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'mysql',
    'host': 'localhost',
    'port': '3306',
    'database': 'banco_teste',
    'username': 'dart',
    'password': 'dart',
    // for SSL conection
    'sslmode': 'require',
    // options not implemented 
    // 'options': {
    //   PDO_MYSQL_ATTR_SSL_VERIFY_SERVER_CERT: false,
    //   PDO_MYSQL_ATTR_SSL_KEY: '/certs/client-key.pem',
    //   PDO_MYSQL_ATTR_SSL_CERT: '/certs/client-cert.pem',
    //   PDO_MYSQL_ATTR_SSL_CA: '/certs/ca.pem',
    // },
    // to enable pool of conections
    // 'pool': true,
    // 'poolsize': 2,
  });

  manager.setAsGlobal();

  final db = await manager.connection();

  await db.execute('DROP TABLE IF EXISTS clients');
  await db.execute(''' CREATE TABLE IF NOT EXISTS clients (
    id int NOT NULL AUTO_INCREMENT,
    name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');

  await db.execute('DROP TABLE contacts');
  await db.execute(''' CREATE TABLE IF NOT EXISTS contacts (
    id_client int NOT NULL ,
    tel varchar(255) NOT NULL  
); ''');

  await db.table('clients').insert({'name': 'Isaque'});
  await db.table('clients').insert({'name': 'John Doe'});
  await db.table('clients').insert({'name': 'Jane Doe'});

  await db
      .table('clients')
      .where('id', '=', 1)
      .update({'name': 'Isaque update'});

  // await db.table('clients').where('id', '=', 2).delete();

  await db.table('contacts').insert({'id_client': 1, 'tel': '27772339'});
  await db.table('contacts').insert({'id_client': 2, 'tel': '99705498'});

  final id = await db.table('clients').insertGetId({'name': 'Jack'});
  print('id: $id');
  var res = await db
      .table('clients')
      .selectRaw('id,name,tel')
      .join('contacts', 'contacts.id_client', '=', 'clients.id')
      .get();

  print('res: $res');
  //res: [{id: 1, name: Isaque update, tel: 27772339}, {id: 2, name: John Doe, tel: 99705498}]
  await db.disconnect();

  exit(0);
}
