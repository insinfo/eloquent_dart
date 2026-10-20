import 'dart:async';

/// FIFO lock for adapters whose single connection runs one command at a time
/// (dpgsql, mysql_dart). Concurrent callers wait their turn, as with the
/// postgres/postgres_v3/dargres adapters, instead of failing with
/// "connection is busy" / "another command is still running".
///
/// Work done through a transaction context does not take the lock (the
/// transaction already holds it), so only calling the outer connection from
/// inside its own transaction would wait forever.
class OperationLock {
  Future<void> _tail = Future<void>.value();

  /// Waits for the previous holders and returns the release function.
  Future<void Function()> acquire() async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    return done.complete;
  }

  /// Runs [operation] when every earlier operation has finished.
  Future<T> run<T>(Future<T> Function() operation) async {
    final release = await acquire();
    try {
      return await operation();
    } finally {
      release();
    }
  }
}
