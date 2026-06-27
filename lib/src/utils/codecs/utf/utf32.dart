library galileo_utf.utf32;

import "dart:collection";

import 'constants.dart';
import 'list_range.dart';
import 'shared.dart';

/// Decodes UTF-32 bytes lazily as an iterable of code points.
///
/// Determines byte order from the BOM, defaults to big-endian, and always
/// strips a leading BOM. Set [replacementCodepoint] to `null` to throw an
/// [ArgumentError] instead of replacing invalid sequences.
IterableUtf32Decoder decodeUtf32AsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf32Decoder._(
      () => Utf32BytesDecoder(bytes, offset, length, replacementCodepoint));
}

/// Decodes UTF-32BE bytes lazily as an iterable of code points.
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
IterableUtf32Decoder decodeUtf32beAsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf32Decoder._(() => Utf32beBytesDecoder(
      bytes, offset, length, stripBom, replacementCodepoint));
}

/// Decodes UTF-32LE bytes lazily as an iterable of code points.
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
IterableUtf32Decoder decodeUtf32leAsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf32Decoder._(() => Utf32leBytesDecoder(
      bytes, offset, length, stripBom, replacementCodepoint));
}

/// Converts UTF-32 encoded bytes into a [String].
///
/// Supports offset/length windows and configurable replacement behavior.
/// Set [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
String decodeUtf32(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return String.fromCharCodes(
      (Utf32BytesDecoder(bytes, offset, length, replacementCodepoint))
          .decodeRest());
}

/// Converts UTF-32BE encoded bytes into a [String].
///
/// Supports offset/length windows and configurable replacement behavior.
/// Set [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
String decodeUtf32be(List<int> bytes,
        [int offset = 0,
        int? length,
        bool stripBom = true,
        int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) =>
    String.fromCharCodes((Utf32beBytesDecoder(
            bytes, offset, length, stripBom, replacementCodepoint))
        .decodeRest());

/// Converts UTF-32LE encoded bytes into a [String].
///
/// Supports offset/length windows and configurable replacement behavior.
/// Set [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences.
String decodeUtf32le(List<int> bytes,
        [int offset = 0,
        int? length,
        bool stripBom = true,
        int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) =>
    String.fromCharCodes((Utf32leBytesDecoder(
            bytes, offset, length, stripBom, replacementCodepoint))
        .decodeRest());

/// Encodes a [String] as UTF-32 bytes with a big-endian BOM.
List<int> encodeUtf32(String str) => encodeUtf32be(str, true);

/// Encodes a [String] as UTF-32BE bytes, optionally prefixing a BOM.
List<int> encodeUtf32be(String str, [bool writeBOM = false]) {
  List<int> utf32CodeUnits = stringToCodepoints(str);
  List<int> encoding = List<int>.filled(
      4 * utf32CodeUnits.length + (writeBOM ? 4 : 0), 0,
      growable: false);
  int i = 0;
  if (writeBOM) {
    encoding[i++] = 0;
    encoding[i++] = 0;
    encoding[i++] = UNICODE_UTF_BOM_HI;
    encoding[i++] = UNICODE_UTF_BOM_LO;
  }
  for (int unit in utf32CodeUnits) {
    encoding[i++] = (unit >> 24) & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit >> 16) & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit >> 8) & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = unit & UNICODE_BYTE_ZERO_MASK;
  }
  return encoding;
}

/// Encodes a [String] as UTF-32LE bytes, optionally prefixing a BOM.
List<int> encodeUtf32le(String str, [bool writeBOM = false]) {
  List<int> utf32CodeUnits = stringToCodepoints(str);
  List<int> encoding = List<int>.filled(
      4 * utf32CodeUnits.length + (writeBOM ? 4 : 0), 0,
      growable: false);
  int i = 0;
  if (writeBOM) {
    encoding[i++] = UNICODE_UTF_BOM_LO;
    encoding[i++] = UNICODE_UTF_BOM_HI;
    encoding[i++] = 0;
    encoding[i++] = 0;
  }
  for (int unit in utf32CodeUnits) {
    encoding[i++] = unit & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit >> 8) & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit >> 16) & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit >> 24) & UNICODE_BYTE_ZERO_MASK;
  }
  return encoding;
}

/// Returns `true` if the bytes starting at [offset] contain any UTF-32 BOM.
bool hasUtf32Bom(List<int> utf32EncodedBytes, [int offset = 0, int? length]) {
  return hasUtf32beBom(utf32EncodedBytes, offset, length) ||
      hasUtf32leBom(utf32EncodedBytes, offset, length);
}

/// Returns `true` if the bytes starting at [offset] contain a UTF-32BE BOM.
bool hasUtf32beBom(List<int> utf32EncodedBytes, [int offset = 0, int? length]) {
  int end = length != null ? offset + length : utf32EncodedBytes.length;
  return (offset + 4) <= end &&
      utf32EncodedBytes[offset] == 0 &&
      utf32EncodedBytes[offset + 1] == 0 &&
      utf32EncodedBytes[offset + 2] == UNICODE_UTF_BOM_HI &&
      utf32EncodedBytes[offset + 3] == UNICODE_UTF_BOM_LO;
}

/// Returns `true` if the bytes starting at [offset] contain a UTF-32LE BOM.
bool hasUtf32leBom(List<int> utf32EncodedBytes, [int offset = 0, int? length]) {
  int end = length != null ? offset + length : utf32EncodedBytes.length;
  return (offset + 4) <= end &&
      utf32EncodedBytes[offset] == UNICODE_UTF_BOM_LO &&
      utf32EncodedBytes[offset + 1] == UNICODE_UTF_BOM_HI &&
      utf32EncodedBytes[offset + 2] == 0 &&
      utf32EncodedBytes[offset + 3] == 0;
}

typedef Utf32BytesDecoderProvider = Utf32BytesDecoder Function();

/// Iterable returned by [decodeUtf32AsIterable] and related helpers.
///
/// Creates decoders on demand and translates bytes only as needed. Results are
/// not cached.
// NOTE(floitsch): Consider removing the extend and switch to implements since
// that's cheaper to allocate.
class IterableUtf32Decoder extends IterableBase<int> {
  final Utf32BytesDecoderProvider codeunitsProvider;

  IterableUtf32Decoder._(this.codeunitsProvider);

  @override
  Utf32BytesDecoder get iterator => codeunitsProvider();
}

/// Base class that converts encoded bytes to UTF-32 code points.
abstract class Utf32BytesDecoder implements ListRangeIterator {
  // NOTE(kevmoo): should this field be private?
  final ListRangeIterator utf32EncodedBytesIterator;
  final int? replacementCodepoint;
  int? _current;

  Utf32BytesDecoder._fromListRangeIterator(
      this.utf32EncodedBytesIterator, this.replacementCodepoint);

  factory Utf32BytesDecoder(List<int> utf32EncodedBytes,
      [int offset = 0,
      int? length,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
    final effectiveLength = length ?? (utf32EncodedBytes.length - offset);
    if (hasUtf32beBom(utf32EncodedBytes, offset, effectiveLength)) {
      return Utf32beBytesDecoder(utf32EncodedBytes, offset + 4,
          effectiveLength - 4, false, replacementCodepoint);
    } else if (hasUtf32leBom(utf32EncodedBytes, offset, effectiveLength)) {
      return Utf32leBytesDecoder(utf32EncodedBytes, offset + 4,
          effectiveLength - 4, false, replacementCodepoint);
    } else {
      return Utf32beBytesDecoder(utf32EncodedBytes, offset, effectiveLength,
          false, replacementCodepoint);
    }
  }

  List<int> decodeRest() {
    List<int> codeunits = List<int>.filled(remaining, 0, growable: false);
    int i = 0;
    while (moveNext()) {
      codeunits[i++] = current;
    }
    return codeunits;
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
    int remaining = utf32EncodedBytesIterator.remaining;
    if (remaining == 0) {
      return false;
    }
    if (remaining < 4) {
      utf32EncodedBytesIterator.skip(utf32EncodedBytesIterator.remaining);
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF32 at ${utf32EncodedBytesIterator.position}");
      }
    }
    int codepoint = decode();
    if (_validCodepoint(codepoint)) {
      _current = codepoint;
      return true;
    } else {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF32 at ${utf32EncodedBytesIterator.position}");
      }
    }
  }

  int get position => utf32EncodedBytesIterator.position ~/ 4;

  @override
  void backup([int by = 1]) {
    utf32EncodedBytesIterator.backup(4 * by);
  }

  @override
  int get remaining => (utf32EncodedBytesIterator.remaining + 3) ~/ 4;

  @override
  void skip([int count = 1]) {
    utf32EncodedBytesIterator.skip(4 * count);
  }

  int decode();
}

/// Converts UTF-32BE encoded bytes to Unicode code points.
class Utf32beBytesDecoder extends Utf32BytesDecoder {
  Utf32beBytesDecoder(List<int> utf32EncodedBytes,
      [int offset = 0,
      int? length,
      bool stripBom = true,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : super._fromListRangeIterator(
            ListRange(utf32EncodedBytes, offset, length).iterator,
            replacementCodepoint) {
    if (stripBom && hasUtf32beBom(utf32EncodedBytes, offset, length)) {
      skip();
    }
  }

  int decode() {
    utf32EncodedBytesIterator.moveNext();
    int value = utf32EncodedBytesIterator.current;
    utf32EncodedBytesIterator.moveNext();
    value = (value << 8) + utf32EncodedBytesIterator.current;
    utf32EncodedBytesIterator.moveNext();
    value = (value << 8) + utf32EncodedBytesIterator.current;
    utf32EncodedBytesIterator.moveNext();
    value = (value << 8) + utf32EncodedBytesIterator.current;
    return value;
  }
}

/// Converts UTF-32LE encoded bytes to Unicode code points.
class Utf32leBytesDecoder extends Utf32BytesDecoder {
  Utf32leBytesDecoder(List<int> utf32EncodedBytes,
      [int offset = 0,
      int? length,
      bool stripBom = true,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : super._fromListRangeIterator(
            ListRange(utf32EncodedBytes, offset, length).iterator,
            replacementCodepoint) {
    if (stripBom && hasUtf32leBom(utf32EncodedBytes, offset, length)) {
      skip();
    }
  }

  int decode() {
    utf32EncodedBytesIterator.moveNext();
    int value = utf32EncodedBytesIterator.current;
    utf32EncodedBytesIterator.moveNext();
    value += (utf32EncodedBytesIterator.current << 8);
    utf32EncodedBytesIterator.moveNext();
    value += (utf32EncodedBytesIterator.current << 16);
    utf32EncodedBytesIterator.moveNext();
    value += (utf32EncodedBytesIterator.current << 24);
    return value;
  }
}

bool _validCodepoint(int codepoint) {
  return (codepoint >= 0 && codepoint < UNICODE_UTF16_RESERVED_LO) ||
      (codepoint > UNICODE_UTF16_RESERVED_HI &&
          codepoint < UNICODE_VALID_RANGE_MAX);
}
