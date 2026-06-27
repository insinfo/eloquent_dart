library galileo_utf.utf_16_code_unit_decoder;

import 'constants.dart';
import 'list_range.dart';

/// An `Iterator<int>` of code points built on an iterator of UTF-16 code units.
///
/// The parameters can override the default Unicode replacement character. Set
/// the replacementCharacter to `null` to throw an [ArgumentError] rather than
/// replace the bad value.
class Utf16CodeUnitDecoder implements Iterator<int> {
  // NOTE(kevmoo): should this field be private?
  final ListRangeIterator utf16CodeUnitIterator;
  final int? replacementCodepoint;
  int? _current;

  Utf16CodeUnitDecoder(List<int> utf16CodeUnits,
      [int offset = 0,
      int? length,
      int? replacementCodepoint = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : utf16CodeUnitIterator =
            ListRange(utf16CodeUnits, offset, length).iterator,
        replacementCodepoint = replacementCodepoint;

  Utf16CodeUnitDecoder.fromListRangeIterator(this.utf16CodeUnitIterator,
      [int? replacement = UNICODE_REPLACEMENT_CHARACTER_CODEPOINT])
      : replacementCodepoint = replacement;

  Iterator<int> get iterator => this;

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
    if (!utf16CodeUnitIterator.moveNext()) return false;

    int value = utf16CodeUnitIterator.current;
    if (value < 0) {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
      } else {
        throw ArgumentError(
            "Invalid UTF16 at ${utf16CodeUnitIterator.position}");
      }
    } else if (value < UNICODE_UTF16_RESERVED_LO ||
        (value > UNICODE_UTF16_RESERVED_HI && value <= UNICODE_PLANE_ONE_MAX)) {
      // transfer directly
      _current = value;
    } else if (value < UNICODE_UTF16_SURROGATE_UNIT_1_BASE &&
        utf16CodeUnitIterator.moveNext()) {
      // merge surrogate pair
      int nextValue = utf16CodeUnitIterator.current;
      if (nextValue >= UNICODE_UTF16_SURROGATE_UNIT_1_BASE &&
          nextValue <= UNICODE_UTF16_RESERVED_HI) {
        value = (value - UNICODE_UTF16_SURROGATE_UNIT_0_BASE) << 10;
        value += UNICODE_UTF16_OFFSET +
            (nextValue - UNICODE_UTF16_SURROGATE_UNIT_1_BASE);
        _current = value;
      } else {
        if (nextValue >= UNICODE_UTF16_SURROGATE_UNIT_0_BASE &&
            nextValue < UNICODE_UTF16_SURROGATE_UNIT_1_BASE) {
          utf16CodeUnitIterator.backup();
        }
        final replacement = replacementCodepoint;
        if (replacement != null) {
          _current = replacement;
        } else {
          throw ArgumentError(
              "Invalid UTF16 at ${utf16CodeUnitIterator.position}");
        }
      }
    } else {
      final replacement = replacementCodepoint;
      if (replacement != null) {
        _current = replacement;
      } else {
        throw ArgumentError(
            "Invalid UTF16 at ${utf16CodeUnitIterator.position}");
      }
    }
    return true;
  }
}
