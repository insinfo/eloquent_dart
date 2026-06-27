library galileo_utf.list_range;

import 'dart:collection';

/// Lightweight view over a range within a source list.
///
/// Do not modify the underlying list while iterating; behavior is undefined.
// NOTE(floitsch): Consider removing the extend and switch to implements since
// that's cheaper to allocate.
class ListRange extends IterableBase<int> {
  final List<int> _source;
  final int _offset;
  final int _length;

  ListRange(List<int> source, [int offset = 0, int? length])
      : _source = source,
        _offset = offset,
        _length = length ?? (source.length - offset) {
    if (_offset < 0 || _offset > _source.length) {
      throw RangeError.value(_offset);
    }
    if (_length < 0) {
      throw RangeError.value(_length);
    }
    if (_length + _offset > _source.length) {
      throw RangeError.value(_length + _offset);
    }
  }

  @override
  ListRangeIterator get iterator =>
      _ListRangeIteratorImpl(_source, _offset, _offset + _length);

  @override
  int get length => _length;
}

/// Iterator with support for tracking position and skipping within the range.
abstract class ListRangeIterator implements Iterator<int> {
  @override
  bool moveNext();

  @override
  int get current;

  int get position;

  void backup([int by = 1]);

  int get remaining;

  void skip([int count = 1]);
}

class _ListRangeIteratorImpl implements ListRangeIterator {
  final List<int> _source;
  int _offset;
  final int _end;

  _ListRangeIteratorImpl(this._source, int offset, this._end)
      : _offset = offset - 1;

  @override
  int get current => _source[_offset];

  @override
  bool moveNext() => ++_offset < _end;

  int get position => _offset;

  @override
  void backup([int by = 1]) {
    _offset -= by;
  }

  @override
  int get remaining => _end - _offset - 1;

  @override
  void skip([int count = 1]) {
    _offset += count;
  }
}
