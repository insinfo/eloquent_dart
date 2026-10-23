// Migrations and seeders. Migrations are classes registered in a map (no code
// generation, works in an AOT build); each up/down runs in a transaction
// together with its row in the migration table.
//
//   dart run bin/migrations.dart
//
// The CLI creates the files for you:
//   dart run eloquent:eloquent make:migration create_posts_table --create=posts
//   dart run eloquent:eloquent make:seeder PostsSeeder
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

class CreateAuthorsAndPosts extends Migration {
  @override
  Future<void> up() async {
    final s = await schema;
    await s.create('ex_authors', (Blueprint t) {
      t.increments('id');
      t.string('name', 80);
      t.timestamps();
    });
    await s.create('ex_posts', (Blueprint t) {
      t.increments('id');
      t.integer('author_id');
      t.string('title');
      t.text('body');
      t.nullable();
      t.boolean('published');
      t.defaultTo(false);
      t.foreign('author_id');
      t.references('id');
      t.on('ex_authors');
      t.onDelete('cascade');
    });
  }

  @override
  Future<void> down() async {
    final s = await schema;
    await s.dropIfExists('ex_posts');
    await s.dropIfExists('ex_authors');
  }
}

class AddAuthorsEmail extends Migration {
  @override
  Future<void> up() async {
    await (await schema).table('ex_authors', (Blueprint t) {
      t.string('email', 120);
      t.nullable();
      t.comment('Contact e-mail.'); // COMMENT ON COLUMN on PostgreSQL
    });
    // Anything the Blueprint does not cover: one statement per call
    await statement('create unique index ex_authors_email_uq '
        'on ex_authors (lower(email))');
  }

  @override
  Future<void> down() async {
    await statement('drop index ex_authors_email_uq');
    await (await schema).table('ex_authors', (Blueprint t) {
      t.dropColumn('email');
    });
  }
}

/// CREATE INDEX CONCURRENTLY cannot run in a transaction.
class IndexPostsTitle extends Migration {
  IndexPostsTitle() {
    withinTransaction = false;
  }

  @override
  Future<void> up() => statement(
      'create index concurrently ex_posts_title_idx on ex_posts (title)');

  @override
  Future<void> down() => statement('drop index ex_posts_title_idx');
}

class AuthorsSeeder extends Seeder {
  @override
  Future<void> run() async {
    final db = await this.db!.connection(connectionName);
    final id = await db
        .table('ex_authors')
        .insertGetId({'name': 'Ana', 'email': 'ana@example.com'});
    await db.table('ex_posts').insert(
        {'author_id': id, 'title': 'Hello', 'body': '...', 'published': true});
  }
}

/// The registry: name (sortable, timestamp first) => factory.
final migrations = <String, Migration Function()>{
  '2026_10_23_000001_create_authors_and_posts': () => CreateAuthorsAndPosts(),
  '2026_10_23_000002_add_authors_email': () => AddAuthorsEmail(),
  '2026_10_23_000003_index_posts_title': () => IndexPostsTitle(),
};

Future<void> main() async {
  final manager = postgresManager();
  final dbm = manager.getDatabaseManager();
  final db = await manager.connection();
  await db.unprepared(
      'drop table if exists ex_posts, ex_authors, ex_migrations cascade');

  final migrator = Migrator(
    DatabaseMigrationRepository(dbm, 'ex_migrations'),
    dbm,
    migrations,
    databaseManager: dbm,
  );

  print('pending: ${await migrator.pending()}');

  // Runs what is pending, in name order; creates the migration table.
  // On PostgreSQL an advisory lock makes two instances deploying at the same
  // time apply each migration once.
  await migrator.runPending();
  await migrator.runPending(); // nothing to migrate

  await SeederRunner(dbm).call(AuthorsSeeder());
  final posts = await db
      .table('ex_posts as p')
      .join('ex_authors as a', 'a.id', '=', 'p.author_id')
      .select(['a.name', 'a.email', 'p.title']).get();
  print('seeded: $posts');

  // Undo the last batch (all three migrations ran in one batch)
  await migrator.rollback();
  print('ex_authors exists: '
      '${await db.getSchemaBuilder().hasTable('ex_authors')}');

  // An existing database whose schema already has a migration: record it
  // without running it (a baseline)
  await migrator.markAsRan(['2026_10_23_000001_create_authors_and_posts']);
  print('pending after baseline: ${await migrator.pending()}');

  await db.unprepared('drop table if exists ex_migrations');
  await db.disconnect();
}
