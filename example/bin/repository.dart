// Data Mapper: plain classes, an EntityMapper that converts them to and from
// rows, and a Repository that reads and writes them.
//
//   dart run bin/repository.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

class Book {
  int? id;
  String title;
  int year;

  Book({this.id, required this.title, required this.year});

  @override
  String toString() => 'Book($id, $title, $year)';
}

final bookMapper = EntityMapper<Book>(
  table: 'ex_books',
  fromRow: (r) => Book(
    id: r['id'] as int,
    title: r['title'] as String,
    year: r['year'] as int,
  ),
  toRow: (b) => {'title': b.title, 'year': b.year}, // the database sets id
  getId: (b) => b.id,
);

/// Queries of the domain go in a subclass.
class BookRepository extends Repository<Book> {
  BookRepository(Connection connection) : super(connection, bookMapper);

  Future<List<Book>> publishedAfter(int year) async =>
      hydrateAll(await query().where('year', '>', year).orderBy('year').get());
}

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await db.unprepared('drop table if exists ex_books; '
      'create table ex_books (id serial primary key, title text, year int)');

  final books = BookRepository(db);

  // save() inserts when there is no id and returns the new one
  final id = await books.save(Book(title: 'Dart in Action', year: 2012));
  await books.save(Book(title: 'Flutter Apprentice', year: 2021));
  await books.save(Book(title: 'Clean Code', year: 2008));

  // ...and updates when there is one
  final book = await books.findOrFail(id);
  book.year = 2013;
  await books.save(book);

  print('all: ${await books.all()}');
  print('after 2010: ${await books.publishedAfter(2010)}');
  print('by title: ${await books.firstBy('title', 'Clean Code')}');
  print('count: ${await books.count()}');

  // Streamed: one entity at a time, constant memory
  await for (final b in books.cursor()) {
    print('cursor: ${b.title}');
  }

  await books.delete(book);
  print('after delete: ${await books.count()}');

  await db.unprepared('drop table ex_books');
  await db.disconnect();
}
