library galileo_utf.utf16;

import "dart:collection";

import 'constants.dart';
import 'list_range.dart';
import 'utf_16_code_unit_decoder.dart';
import 'util.dart';

/// Generate a string from the provided Unicode code points.
/// Return type of [decodeUtf16AsIterable] and variants.
///
/// The iterable creates a decoder on demand and only translates bytes as they
/// are requested. Results are not cached.

/// Decodes UTF-16 bytes lazily as an iterable of code units.
///
/// Determines byte order from the BOM, or defaults to big-endian. Always
/// strips a leading BOM. Set [replacementCodepoint] to `null` to throw an
/// [ArgumentError] instead of replacing invalid sequences. Defaults to U+FFFD.
IterableUtf16Decoder decodeUtf16AsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf16Decoder._(
      () => Utf16BytesToCodeUnitsDecoder(
          bytes, offset, length, replacementCodepoint),
      replacementCodepoint);
}

/// Decodes UTF-16BE bytes lazily as an iterable of code units.
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences. Defaults to U+FFFD.
IterableUtf16Decoder decodeUtf16beAsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf16Decoder._(
      () => Utf16beBytesToCodeUnitsDecoder(
          bytes, offset, length, stripBom, replacementCodepoint),
      replacementCodepoint);
}

/// Decodes UTF-16LE bytes lazily as an iterable of code units.
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences. Defaults to U+FFFD.
IterableUtf16Decoder decodeUtf16leAsIterable(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  return IterableUtf16Decoder._(
      () => Utf16leBytesToCodeUnitsDecoder(
          bytes, offset, length, stripBom, replacementCodepoint),
      replacementCodepoint);
}

/// Converts UTF-16 encoded bytes into a [String].
///
/// Always strips a leading BOM. Set [replacementCodepoint] to `null` to throw
/// an [ArgumentError] instead of replacing invalid sequences. Defaults to
/// U+FFFD.
String decodeUtf16(List<int> bytes,
    [int offset = 0,
    int? length,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  final decoder =
      Utf16BytesToCodeUnitsDecoder(bytes, offset, length, replacementCodepoint);
  List<int> codeunits = decoder.decodeRest();
  return String.fromCharCodes(
      utf16CodeUnitsToCodepoints(codeunits, 0, null, replacementCodepoint));
}

/// Converts UTF-16BE encoded bytes into a [String].
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences. Defaults to U+FFFD.
String decodeUtf16be(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  List<int> codeunits = (Utf16beBytesToCodeUnitsDecoder(
          bytes, offset, length, stripBom, replacementCodepoint))
      .decodeRest();
  return String.fromCharCodes(
      utf16CodeUnitsToCodepoints(codeunits, 0, null, replacementCodepoint));
}

/// Converts UTF-16LE encoded bytes into a [String].
///
/// Strips a leading BOM unless [stripBom] is `false`. Set
/// [replacementCodepoint] to `null` to throw an [ArgumentError] instead of
/// replacing invalid sequences. Defaults to U+FFFD.
String decodeUtf16le(List<int> bytes,
    [int offset = 0,
    int? length,
    bool stripBom = true,
    int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
  List<int> codeunits = (Utf16leBytesToCodeUnitsDecoder(
          bytes, offset, length, stripBom, replacementCodepoint))
      .decodeRest();
  return String.fromCharCodes(
      utf16CodeUnitsToCodepoints(codeunits, 0, null, replacementCodepoint));
}

/// Encodes a [String] as UTF-16 bytes with a big-endian BOM.
List<int> encodeUtf16(String str) => encodeUtf16be(str, true);

/// Encodes a [String] as UTF-16BE bytes, optionally prefixing a BOM.
List<int> encodeUtf16be(String str, [bool writeBOM = false]) {
  List<int> utf16CodeUnits = _stringToUtf16CodeUnits(str);
  List<int> encoding = List<int>.filled(
      2 * utf16CodeUnits.length + (writeBOM ? 2 : 0), 0,
      growable: false);
  int i = 0;
  if (writeBOM) {
    encoding[i++] = UNICODE_UTF_BOM_HI;
    encoding[i++] = UNICODE_UTF_BOM_LO;
  }
  for (int unit in utf16CodeUnits) {
    encoding[i++] = (unit & UNICODE_BYTE_ONE_MASK) >> 8;
    encoding[i++] = unit & UNICODE_BYTE_ZERO_MASK;
  }
  return encoding;
}

/// Encodes a [String] as UTF-16LE bytes, optionally prefixing a BOM.
List<int> encodeUtf16le(String str, [bool writeBOM = false]) {
  List<int> utf16CodeUnits = _stringToUtf16CodeUnits(str);
  List<int> encoding = List<int>.filled(
      2 * utf16CodeUnits.length + (writeBOM ? 2 : 0), 0,
      growable: false);
  int i = 0;
  if (writeBOM) {
    encoding[i++] = UNICODE_UTF_BOM_LO;
    encoding[i++] = UNICODE_UTF_BOM_HI;
  }
  for (int unit in utf16CodeUnits) {
    encoding[i++] = unit & UNICODE_BYTE_ZERO_MASK;
    encoding[i++] = (unit & UNICODE_BYTE_ONE_MASK) >> 8;
  }
  return encoding;
}

/// Returns `true` if the bytes starting at [offset] contain any UTF-16 BOM.
bool hasUtf16Bom(List<int> utf32EncodedBytes, [int offset = 0, int? length]) {
  return hasUtf16beBom(utf32EncodedBytes, offset, length) ||
      hasUtf16leBom(utf32EncodedBytes, offset, length);
}

/// Returns `true` if the bytes starting at [offset] contain a UTF-16BE BOM.
bool hasUtf16beBom(List<int> utf16EncodedBytes, [int offset = 0, int? length]) {
  int end = length != null ? offset + length : utf16EncodedBytes.length;
  return (offset + 2) <= end &&
      utf16EncodedBytes[offset] == UNICODE_UTF_BOM_HI &&
      utf16EncodedBytes[offset + 1] == UNICODE_UTF_BOM_LO;
}

/// Returns `true` if the bytes starting at [offset] contain a UTF-16LE BOM.
bool hasUtf16leBom(List<int> utf16EncodedBytes, [int offset = 0, int? length]) {
  int end = length != null ? offset + length : utf16EncodedBytes.length;
  return (offset + 2) <= end &&
      utf16EncodedBytes[offset] == UNICODE_UTF_BOM_LO &&
      utf16EncodedBytes[offset + 1] == UNICODE_UTF_BOM_HI;
}

List<int> _stringToUtf16CodeUnits(String str) {
  return codepointsToUtf16CodeUnits(str.codeUnits);
}

typedef _CodeUnitsProvider = ListRangeIterator Function();

/// Iterable returned by [decodeUtf16AsIterable] and related helpers.
///
/// Creates decoders on demand and translates bytes only as needed. Results are
/// not cached.
// NOTE(floitsch): Consider removing the extend and switch to implements since
// that's cheaper to allocate.
class IterableUtf16Decoder extends IterableBase<int> {
  final _CodeUnitsProvider codeunitsProvider;
  final int? replacementCodepoint;

  IterableUtf16Decoder._(this.codeunitsProvider, this.replacementCodepoint);

  @override
  Utf16CodeUnitDecoder get iterator =>
      Utf16CodeUnitDecoder.fromListRangeIterator(
          codeunitsProvider(), replacementCodepoint);
}

/// Converts UTF-16 encoded bytes to code units by grouping 1–2 bytes.
///
/// Uses the BOM to determine endianness and defaults to big-endian.
abstract class Utf16BytesToCodeUnitsDecoder implements ListRangeIterator {
  // NOTE(kevmoo): should this field be private?
  final ListRangeIterator utf16EncodedBytesIterator;
  final int? replacementCodepoint;
  int? _current;

  Utf16BytesToCodeUnitsDecoder._fromListRangeIterator(
      this.utf16EncodedBytesIterator, this.replacementCodepoint);

  factory Utf16BytesToCodeUnitsDecoder(List<int> utf16EncodedBytes,
      [int offset = 0,
      int? length,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT]) {
    final effectiveLength = length ?? (utf16EncodedBytes.length - offset);
    if (hasUtf16beBom(utf16EncodedBytes, offset, effectiveLength)) {
      return Utf16beBytesToCodeUnitsDecoder(utf16EncodedBytes, offset + 2,
          effectiveLength - 2, false, replacementCodepoint);
    } else if (hasUtf16leBom(utf16EncodedBytes, offset, effectiveLength)) {
      return Utf16leBytesToCodeUnitsDecoder(utf16EncodedBytes, offset + 2,
          effectiveLength - 2, false, replacementCodepoint);
    } else {
      return Utf16beBytesToCodeUnitsDecoder(utf16EncodedBytes, offset,
          effectiveLength, false, replacementCodepoint);
    }
  }

  /// Decodes the remaining bytes in one pass.
  ///
  /// Potentially over-allocates the result for speed, then truncates as
  /// needed.
  List<int> decodeRest() {
    List<int> codeunits = List<int>.filled(remaining, 0, growable: false);
    int i = 0;
    while (moveNext()) {
      codeunits[i++] = current;
    }
    if (i == codeunits.length) {
      return codeunits;
    } else {
      List<int> truncCodeunits = List<int>.filled(i, 0, growable: false);
      truncCodeunits.setRange(0, i, codeunits);
      return truncCodeunits;
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
    int remaining = utf16EncodedBytesIterator.remaining;
    if (remaining == 0) {
      return false;
    }
    if (remaining == 1) {
      utf16EncodedBytesIterator.moveNext();
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
        return true;
      } else {
        throw ArgumentError(
            "Invalid UTF16 at ${utf16EncodedBytesIterator.position}");
      }
    }
    _current = decode();
    return true;
  }

  int get position => utf16EncodedBytesIterator.position ~/ 2;

  @override
  void backup([int by = 1]) {
    utf16EncodedBytesIterator.backup(2 * by);
  }

  @override
  int get remaining => (utf16EncodedBytesIterator.remaining + 1) ~/ 2;

  @override
  void skip([int count = 1]) {
    utf16EncodedBytesIterator.skip(2 * count);
  }

  int decode();
}

/// Converts UTF-16BE encoded bytes to UTF-16 code units.
class Utf16beBytesToCodeUnitsDecoder extends Utf16BytesToCodeUnitsDecoder {
  Utf16beBytesToCodeUnitsDecoder(List<int> utf16EncodedBytes,
      [int offset = 0,
      int? length,
      bool stripBom = true,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : super._fromListRangeIterator(
            ListRange(utf16EncodedBytes, offset, length).iterator,
            replacementCodepoint) {
    if (stripBom && hasUtf16beBom(utf16EncodedBytes, offset, length)) {
      skip();
    }
  }

  int decode() {
    utf16EncodedBytesIterator.moveNext();
    int hi = utf16EncodedBytesIterator.current;
    utf16EncodedBytesIterator.moveNext();
    int lo = utf16EncodedBytesIterator.current;
    return (hi << 8) + lo;
  }
}

/// Converts UTF-16LE encoded bytes to UTF-16 code units.
class Utf16leBytesToCodeUnitsDecoder extends Utf16BytesToCodeUnitsDecoder {
  Utf16leBytesToCodeUnitsDecoder(List<int> utf16EncodedBytes,
      [int offset = 0,
      int? length,
      bool stripBom = true,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : super._fromListRangeIterator(
            ListRange(utf16EncodedBytes, offset, length).iterator,
            replacementCodepoint) {
    if (stripBom && hasUtf16leBom(utf16EncodedBytes, offset, length)) {
      skip();
    }
  }

  int decode() {
    utf16EncodedBytesIterator.moveNext();
    int lo = utf16EncodedBytesIterator.current;
    utf16EncodedBytesIterator.moveNext();
    int hi = utf16EncodedBytesIterator.current;
    return (hi << 8) + lo;
  }
}
