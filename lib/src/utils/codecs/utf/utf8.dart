library galileo_utf.utf8;

import "dart:collection";

import 'constants.dart';
import 'list_range.dart';
import 'shared.dart';

const int _UTF8_ONE_BYTE_MAX = 0x7f;
const int _UTF8_TWO_BYTE_MAX = 0x7ff;
const int _UTF8_THREE_BYTE_MAX = 0xffff;

const int _UTF8_LO_SIX_BIT_MASK = 0x3f;

const int _UTF8_FIRST_BYTE_OF_TWO_BASE = 0xc0;
const int _UTF8_FIRST_BYTE_OF_THREE_BASE = 0xe0;
const int _UTF8_FIRST_BYTE_OF_FOUR_BASE = 0xf0;
const int _UTF8_FIRST_BYTE_OF_FIVE_BASE = 0xf8;
const int _UTF8_FIRST_BYTE_OF_SIX_BASE = 0xfc;

const int _UTF8_FIRST_BYTE_OF_TWO_MASK = 0x1f;
const int _UTF8_FIRST_BYTE_OF_THREE_MASK = 0xf;
const int _UTF8_FIRST_BYTE_OF_FOUR_MASK = 0x7;

const int _UTF8_FIRST_BYTE_BOUND_EXCL = 0xfe;
const int _UTF8_SUBSEQUENT_BYTE_BASE = 0x80;

/// Decodes UTF-8 bytes lazily as an iterable of code points.
///
/// Set [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
IterableUtf8Decoder decodeUtf8AsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf8Decoder(bytes, offset, length, replacementCodepoint);
}

/// Converts UTF-8 encoded bytes into a [String].
///
/// Supports offset/length windows and configurable replacement behavior. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
String decodeUtf8(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return String.fromCharCodes(
      (Utf8Decoder(bytes, offset, length, replacementCodepoint)).decodeRest());
}

/// Encodes a [String] as UTF-8 bytes.
List<int> encodeUtf8(String str) => codepointsToUtf8(stringToCodepoints(str));

int _addToEncoding(int offset, int bytes, int value, List<int> buffer) {
  while (bytes > 0) {
    buffer[offset + bytes] =
        _UTF8_SUBSEQUENT_BYTE_BASE | (value & _UTF8_LO_SIX_BIT_MASK);
    value = value >> 6;
    bytes--;
  }
  return value;
}

/// Encodes Unicode code points as UTF-8 code units.
List<int> codepointsToUtf8(List<int> codepoints,
    [int offset = 0, int? length]) {
  ListRange source = ListRange(codepoints, offset, length);

  int encodedLength = 0;
  for (int value in source) {
    if (value < 0 || value > UNICODE_VALID_RANGE_MAX) {
      encodedLength += 3;
    } else if (value <= _UTF8_ONE_BYTE_MAX) {
      encodedLength++;
    } else if (value <= _UTF8_TWO_BYTE_MAX) {
      encodedLength += 2;
    } else if (value <= _UTF8_THREE_BYTE_MAX) {
      encodedLength += 3;
    } else if (value <= UNICODE_VALID_RANGE_MAX) {
      encodedLength += 4;
    }
  }

  List<int> encoded = List<int>.filled(encodedLength, 0, growable: false);
  int insertAt = 0;
  for (int value in source) {
    if (value < 0 || value > UNICODE_VALID_RANGE_MAX) {
      encoded.setRange(insertAt, insertAt + 3, [0xef, 0xbf, 0xbd]);
      insertAt += 3;
    } else if (value <= _UTF8_ONE_BYTE_MAX) {
      encoded[insertAt] = value;
      insertAt++;
    } else if (value <= _UTF8_TWO_BYTE_MAX) {
      encoded[insertAt] = _UTF8_FIRST_BYTE_OF_TWO_BASE |
          (_UTF8_FIRST_BYTE_OF_TWO_MASK &
              _addToEncoding(insertAt, 1, value, encoded));
      insertAt += 2;
    } else if (value <= _UTF8_THREE_BYTE_MAX) {
      encoded[insertAt] = _UTF8_FIRST_BYTE_OF_THREE_BASE |
          (_UTF8_FIRST_BYTE_OF_THREE_MASK &
              _addToEncoding(insertAt, 2, value, encoded));
      insertAt += 3;
    } else if (value <= UNICODE_VALID_RANGE_MAX) {
      encoded[insertAt] = _UTF8_FIRST_BYTE_OF_FOUR_BASE |
          (_UTF8_FIRST_BYTE_OF_FOUR_MASK &
              _addToEncoding(insertAt, 3, value, encoded));
      insertAt += 4;
    }
  }
  return encoded;
}

// Because UTF-8 specifies byte order, we do not have to follow the pattern
// used by UTF-16 & UTF-32 regarding byte order.
List<int> utf8ToCodepoints(List<int> utf8EncodedBytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return Utf8Decoder(utf8EncodedBytes, offset, length, replacementCodepoint)
      .decodeRest();
}

/// Iterable returned by [decodeUtf8AsIterable] and related helpers.
///
/// Creates decoders on demand and translates bytes only as needed. Results are
/// not cached.
// NOTE(floitsch): Consider removing the extend and switch to implements since
// that's cheaper to allocate.
class IterableUtf8Decoder extends IterableBase<int> {
  final List<int> bytes;
  final int offset;
  final int? _length;
  final int? replacementCodepoint;

  IterableUtf8Decoder(this.bytes,
      [this.offset = 0,
      int? length,
      this.replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : _length = length;

  @override
  Utf8Decoder get iterator =>
      Utf8Decoder(bytes, offset, _length, replacementCodepoint);
}

/// Provides an iterator of UTF-8 encoded bytes as Unicode code points.
///
/// Supports offset/length windows and configurable replacement behavior. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences. The iterator itself is iterable.
class Utf8Decoder implements Iterator<int> {
  // NOTE(kevmoo): should this field be private?
  final ListRangeIterator utf8EncodedBytesIterator;
  final int? replacementCodepoint;
  int? _current;

  Utf8Decoder(List<int> utf8EncodedBytes,
      [int offset = 0,
      int? length,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : utf8EncodedBytesIterator =
            ListRange(utf8EncodedBytes, offset, length).iterator,
        replacementCodepoint = replacementCodepoint;

  Utf8Decoder.fromListRangeIterator(ListRange source,
      [int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : utf8EncodedBytesIterator = source.iterator,
        replacementCodepoint = replacementCodepoint;

  /// Decodes the remaining characters in this decoder into a [List] of code
  /// points.
  List<int> decodeRest() {
    List<int> codepoints = List<int>.filled(
        utf8EncodedBytesIterator.remaining, 0,
        growable: false);
    int i = 0;
    while (moveNext()) {
      codepoints[i++] = current;
    }
    if (i == codepoints.length) {
      return codepoints;
    } else {
      List<int> truncCodepoints = List<int>.filled(i, 0, growable: false);
      truncCodepoints.setRange(0, i, codepoints);
      return truncCodepoints;
    }
  }

  @override
  int get current {
    final value = _current;
    if (value == null) {
      throw StateError('No element');
    }
    return value;
  }

  @override
  bool moveNext() {
    _current = null;

    if (!utf8EncodedBytesIterator.moveNext()) return false;

    int value = utf8EncodedBytesIterator.current;
    int additionalBytes = 0;

    if (value < 0) {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF8 at ${utf8EncodedBytesIterator.position}");
      }
    } else if (value <= _UTF8_ONE_BYTE_MAX) {
      _current = value;
      return true;
    } else if (value < _UTF8_FIRST_BYTE_OF_TWO_BASE) {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF8 at ${utf8EncodedBytesIterator.position}");
      }
    } else if (value < _UTF8_FIRST_BYTE_OF_THREE_BASE) {
      value -= _UTF8_FIRST_BYTE_OF_TWO_BASE;
      additionalBytes = 1;
    } else if (value < _UTF8_FIRST_BYTE_OF_FOUR_BASE) {
      value -= _UTF8_FIRST_BYTE_OF_THREE_BASE;
      additionalBytes = 2;
    } else if (value < _UTF8_FIRST_BYTE_OF_FIVE_BASE) {
      value -= _UTF8_FIRST_BYTE_OF_FOUR_BASE;
      additionalBytes = 3;
    } else if (value < _UTF8_FIRST_BYTE_OF_SIX_BASE) {
      value -= _UTF8_FIRST_BYTE_OF_FIVE_BASE;
      additionalBytes = 4;
    } else if (value < _UTF8_FIRST_BYTE_BOUND_EXCL) {
      value -= _UTF8_FIRST_BYTE_OF_SIX_BASE;
      additionalBytes = 5;
    } else {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF8 at ${utf8EncodedBytesIterator.position}");
      }
    }
    int j = 0;
    while (j < additionalBytes && utf8EncodedBytesIterator.moveNext()) {
      int nextValue = utf8EncodedBytesIterator.current;
      if (nextValue > _UTF8_ONE_BYTE_MAX &&
          nextValue < _UTF8_FIRST_BYTE_OF_TWO_BASE) {
        value = ((value << 6) | (nextValue & _UTF8_LO_SIX_BIT_MASK));
      } else {
        // if sequence-starting code unit, reposition cursor to start here
        if (nextValue >= _UTF8_FIRST_BYTE_OF_TWO_BASE) {
          utf8EncodedBytesIterator.backup();
        }
        break;
      }
      j++;
    }
    bool validSequence = (j == additionalBytes &&
        (value < UNICODE_UTF16_RESERVED_LO ||
            value > UNICODE_UTF16_RESERVED_HI));
    bool nonOverlong = (additionalBytes == 1 && value > _UTF8_ONE_BYTE_MAX) ||
        (additionalBytes == 2 && value > _UTF8_TWO_BYTE_MAX) ||
        (additionalBytes == 3 && value > _UTF8_THREE_BYTE_MAX);
    bool inRange = value <= UNICODE_VALID_RANGE_MAX;
    if (validSequence && nonOverlong && inRange) {
      _current = value;
      return true;
    } else {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF8 at ${utf8EncodedBytesIterator.position - j}");
      }
    }
  }
}
