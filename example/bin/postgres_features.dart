// PostgreSQL features: jsonb, arrays, full-text search, DISTINCT ON and
// LISTEN/NOTIFY.
//
//   dart run bin/postgres_features.dart
import 'dart:async';

import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await db.unprepared('''
    drop table if exists ex_docs, ex_events;
    create table ex_docs (id serial primary key, title text, body text,
                          tags text[], meta jsonb);
    create table ex_events (id serial primary key, user_id int, kind text,
                            created_at timestamp);
  ''');

  // A List goes to a text[] column; jsonb takes encoded JSON
  await db.table('ex_docs').insert({
    'title': 'Quick fox',
    'body': 'The quick brown fox jumps over the lazy dog',
    'tags': ['animals', 'urgent'],
    'meta': '{"author": "ana", "pages": 3}',
  });
  await db.table('ex_docs').insert({
    'title': 'Cats and dogs',
    'body': 'Cats sleep while dogs run',
    'tags': ['animals'],
    'meta': '{"author": "bruno", "pages": 12}',
  });

  // jsonb: containment and the -> selector ("meta"->>'author')
  final byAna = await db
      .table('ex_docs')
      .whereJsonContains('meta', {'author': 'ana'}).pluck('title');
  final byBruno = await db
      .table('ex_docs')
      .where('meta->author', '=', 'bruno')
      .pluck('title');
  print('json: $byAna, $byBruno');

  // Arrays: @> (contains), && (overlaps); they come back as List
  final urgent =
      await db.table('ex_docs').whereArrayContains('tags', ['urgent']).first();
  final overlapping = await db
      .table('ex_docs')
      .whereArrayOverlaps('tags', ['animals', 'x']).count();
  print('urgent: ${urgent?['title']} tags=${urgent?['tags']}, '
      'overlapping: $overlapping');

  // Full-text search (to_tsvector/websearch_to_tsquery)
  final found = await db
      .table('ex_docs')
      .whereFullText(['title', 'body'], 'fox OR cats',
          {'language': 'english', 'mode': 'websearch'})
      .pluck('title');
  print('full text: $found');

  // DISTINCT ON: the latest event of each user
  final now = DateTime.now();
  for (var i = 0; i < 6; i++) {
    await db.table('ex_events').insert({
      'user_id': i % 2 + 1,
      'kind': 'event $i',
      'created_at': now.add(Duration(minutes: i)),
    });
  }
  final latest = await db
      .table('ex_events')
      .distinctOn(['user_id'])
      .select(['user_id', 'kind'])
      .orderBy('user_id')
      .orderBy('created_at', 'desc')
      .get();
  print('latest per user: $latest');

  // LISTEN/NOTIFY: one dedicated connection that reconnects by itself.
  // Inside a transaction the notification is delivered on COMMIT.
  final received = Completer<String>();
  final sub = db.notifications('ex_channel').listen((n) {
    if (!received.isCompleted) received.complete(n.payload);
  });
  await db.notificationListener.ready(); // LISTEN is active
  await db.transaction((ctx) async {
    await ctx.notify('ex_channel', 'doc ${urgent?['id']} changed');
  });
  print('notification: '
      '${await received.future.timeout(const Duration(seconds: 5))}');
  await sub.cancel(); // UNLISTEN

  await db.unprepared('drop table ex_docs, ex_events');
  await db.disconnect();
}
