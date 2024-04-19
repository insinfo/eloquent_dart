
library executor;

import 'dart:async';
import 'dart:collection';

import 'package:stack_trace/stack_trace.dart';


/// An async task that completes with a Future or a value.
typedef AsyncTask<R> = FutureOr<R>? Function();

/// An async task that completes after the Stream is closed.
typedef StreamTask<R> = Stream<R>? Function();

/// No more than [maximum] tasks can be started over any given [period].
class Rate {
  /// The maximum number of tasks to start in any given [period].
  final int maximum;

  /// The period of the [Rate], in which [maximum] tasks can be started.
  final Duration period;

  /// Creates a rate limit.
  const Rate(this.maximum, this.period);

  /// Creates a rate limit per second.
  factory Rate.perSecond(int maximum) => Rate(maximum, Duration(seconds: 1));

  /// Creates a rate limit per minute.
  factory Rate.perMinute(int maximum) => Rate(maximum, Duration(minutes: 1));

  /// Creates a rate limit per hour.
  factory Rate.perHour(int maximum) => Rate(maximum, Duration(hours: 1));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rate &&
          runtimeType == other.runtimeType &&
          maximum == other.maximum &&
          period == other.period;

  @override
  int get hashCode => maximum.hashCode ^ period.hashCode;
}

/// Executes async tasks with a configurable maximum [concurrency] and [rate].
abstract class Executor {
  /// The maximum number of tasks running concurrently.
  int concurrency = 1;

  /// The maximum rate of how frequently tasks can be started.
  Rate? rate;

  /// Async task executor.
  factory Executor({
    int concurrency = 1,
    Rate? rate,
  }) =>
      _Executor(concurrency, rate);

  /// The number of tasks that are currently running.
  int get runningCount;

  /// The number of tasks that are currently waiting to be started.
  int get waitingCount;

  /// The total number of tasks scheduled ([runningCount] + [waitingCount]).
  int get scheduledCount;

  /// Schedules an async task and returns with a future that completes when the
  /// task is finished. Task may not get executed immediately.
  Future<R> scheduleTask<R>(AsyncTask<R> task);

  /// Schedules an async task and returns its stream. The task is considered
  /// running until the stream is closed.
  Stream<R> scheduleStream<R>(StreamTask<R> task);

  /// Returns a [Future] that completes when all currently running tasks
  /// complete.
  ///
  /// If [withWaiting] is set, it will include the waiting tasks too.
  Future<List<Object?>> join({bool withWaiting = false});

  /// Notifies the listeners about a state change in [Executor], for example:
  /// - one or more tasks have started
  /// - one or more tasks have completed
  ///
  /// Clients can use this to monitor [scheduledCount] and queue more tasks to
  /// ensure [Executor] is running on full capacity.
  Stream get onChange;

  /// Closes the executor and reject  tasks.
  Future close();
}

class _Executor implements Executor {
  int _concurrency;
  Rate? _rate;
  final ListQueue<_Item<Object?>> _waiting = ListQueue<_Item<Object?>>();
  final ListQueue<_Item<Object?>> _running = ListQueue<_Item<Object?>>();
  final ListQueue<DateTime> _started = ListQueue<DateTime>();
  final StreamController _onChangeController = StreamController.broadcast();
  bool _closing = false;
  Timer? _triggerTimer;

  _Executor(this._concurrency, this._rate) {
    assert(_concurrency > 0);
  }

  @override
  int get runningCount => _running.length;

  @override
  int get waitingCount => _waiting.length;

  @override
  int get scheduledCount => runningCount + waitingCount;

  bool get isClosing => _closing;

  @override
  int get concurrency => _concurrency;

  @override
  set concurrency(int value) {
    if (_concurrency == value) return;
    assert(value > 0);
    _concurrency = value;
    _trigger();
  }

  @override
  Rate? get rate => _rate;

  @override
  set rate(Rate? value) {
    if (_rate == value) return;
    _rate = value;
    _trigger();
  }

  @override
  Future<R> scheduleTask<R>(AsyncTask<R> task) async {
    if (isClosing) throw Exception('Executor doesn\'t accept  tasks.');
    final item = _Item<R?>();
    _waiting.add(item);
    _trigger();
    await item.trigger.future;
    if (isClosing) {
      item.result.completeError(
          TimeoutException('Executor is closing'), Trace.current(1));
    } else {
      try {
        final r = await task();
        item.result.complete(r);
      } catch (e, st) {
        final chain = Chain([Trace.from(st), Trace.current(1)]);
        item.result.completeError(e, chain);
      }
    }
    _running.remove(item);
    _trigger();
    item.done.complete();
    return await item.result.future
        // Nullable R is used to allow using catchError with null output, so
        // we must convert R? into R for the caller
        .then((v) => v as R);
  }

  @override
  Stream<R> scheduleStream<R>(StreamTask<R> task) {
    final streamController = StreamController<R>();
    StreamSubscription<R>? streamSubscription;
    final resourceCompleter = Completer();
    complete() {
      if (streamSubscription != null) {
        streamSubscription?.cancel();
        streamSubscription = null;
      }
      if (!resourceCompleter.isCompleted) {
        resourceCompleter.complete();
      }
      if (!streamController.isClosed) {
        streamController.close();
      }
    }

    completeWithError(e, st) {
      if (!streamController.isClosed) {
        streamController.addError(e as Object, st as StackTrace);
      }
      complete();
    }

    streamController
      ..onCancel = complete
      ..onPause = (() => streamSubscription?.pause())
      ..onResume = () => streamSubscription?.resume();
    scheduleTask(() {
      if (resourceCompleter.isCompleted) return null;
      try {
        final stream = task();
        if (stream == null) {
          complete();
          return null;
        }
        streamSubscription = stream.listen(streamController.add,
            onError: streamController.addError,
            onDone: complete,
            cancelOnError: true);
      } catch (e, st) {
        completeWithError(e, st);
      }
      return resourceCompleter.future;
    }).catchError(completeWithError);
    return streamController.stream;
  }

  @override
  Future<List<Object?>> join({bool withWaiting = false}) {
    final futures = <Future<Object?>>[];
    for (final item in _running) {
      futures.add(item.result.future.catchError((_) async => null));
    }
    if (withWaiting) {
      for (final item in _waiting) {
        futures.add(item.result.future.catchError((_) async => null));
      }
    }
    if (futures.isEmpty) return Future.value([]);
    return Future.wait(futures);
  }

  @override
  Stream get onChange => _onChangeController.stream;

  @override
  Future close() async {
    _closing = true;
    _trigger();
    await join(withWaiting: true);
    _triggerTimer?.cancel();
    await _onChangeController.close();
  }

  void _trigger() {
    _triggerTimer?.cancel();
    _triggerTimer = null;

    while (_running.length < _concurrency && _waiting.isNotEmpty) {
      final rate = _rate;
      if (rate != null) {
        final now = DateTime.now();
        final limitStart = now.subtract(rate.period);
        while (_started.isNotEmpty && _started.first.isBefore(limitStart)) {
          _started.removeFirst();
        }
        if (_started.isNotEmpty) {
          final gap = rate.period ~/ rate.maximum;
          final last = now.difference(_started.last);
          if (gap > last) {
            final diff = gap - last;
            _triggerTimer ??= Timer(diff, _trigger);
            return;
          }
        }
        _started.add(now);
      }

      final item = _waiting.removeFirst();
      _running.add(item);
      item.done.future.whenComplete(() {
        _trigger();
        if (!_closing &&
            _onChangeController.hasListener &&
            !_onChangeController.isClosed) {
          _onChangeController.add(null);
        }
      });
      item.trigger.complete();
    }
  }
}

class _Item<R> {
  final trigger = Completer();
  // Nullable R is used here so that we can return null during catchError
  final result = Completer<R?>();
  final done = Completer();
}