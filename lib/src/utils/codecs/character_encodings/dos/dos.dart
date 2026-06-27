import '../base.dart';

/// Contains base classes for DOS codepage codecs

/// Commonly used DOS code pages start block
const String _dosCodePageCommonStartBlock = '☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼';

/// Provides a DOS codepage decoder.
class DosCodePageDecoder extends BaseDecoder {
  /// Creates a new windows codepage decoder.
  ///
  /// The [symbols] need to be exactly `128` characters long.
  ///
  /// Set [allowInvalid] to true in case invalid characters sequences
  /// should be at least readable.
  const DosCodePageDecoder(
    String symbols, {
    bool allowInvalid = false,
  }) : super.withNonAsciiStartBlock(
          _dosCodePageCommonStartBlock,
          symbols,
          0x7e,
          allowInvalid: allowInvalid,
        );
}

/// Provides a simple windows codepage encoder.
class DosCodePageEncoder extends BaseEncoder {
  /// Creates a new windows codepage encoder.
  ///
  /// Set [allowInvalid] to true in case invalid characters
  /// should be translated to question marks.
  const DosCodePageEncoder(Map<int, int> encodingMap,
      {bool allowInvalid = false})
      : super(
          encodingMap,
          0x7F,
          allowInvalid: allowInvalid,
          lowerEndIndex: 0x1F,
        );
}
