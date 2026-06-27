import '../base.dart';

/// Contains base classes for windows codepage codecs

/// Provides a windows codepage decoder.
class WindowsDecoder extends BaseDecoder {
  /// Creates a new windows codepage decoder.
  ///
  /// The [symbols] need to be exactly `128` characters long.
  ///
  /// Set [allowInvalid] to true in case invalid characters sequences
  /// should be at least readable.
  const WindowsDecoder(String symbols, {bool allowInvalid = false})
      : super(symbols, 0x7F, allowInvalid: allowInvalid);
}

/// Provides a simple windows codepage encoder.
class WindowsEncoder extends BaseEncoder {
  /// Creates a new windows codepage encoder.
  ///
  /// Set [allowInvalid] to true in case invalid characters
  /// should be translated to question marks.
  const WindowsEncoder(Map<int, int> encodingMap, {bool allowInvalid = false})
      : super(encodingMap, 0x7F, allowInvalid: allowInvalid);
}
