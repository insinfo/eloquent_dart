import '../base.dart';

/// Contains base classes for latin 2  to latin 16 / ISO-8859-XX codecs

/// Provides an ISO-8859-XX  decoder.
class LatinDecoder extends BaseDecoder {
  /// Creates a new latin 1 decoder.
  ///
  /// The [symbols] need to be exactly `95` characters long.
  ///
  /// Set [allowInvalid] to true in case invalid characters sequences
  /// should be at least readable.
  const LatinDecoder(String symbols, {bool allowInvalid = false})
      : super(symbols, 0xA0, allowInvalid: allowInvalid);
}

/// Provides an ISO-8859-XX encoder.
class LatinEncoder extends BaseEncoder {
  /// Creates a new latin / iso-8859-XX encoder.
  ///
  /// Set [allowInvalid] to true in case invalid characters should be
  /// translated to question marks.
  const LatinEncoder(Map<int, int> encodingMap, {bool allowInvalid = false})
      : super(encodingMap, 0xA0, allowInvalid: allowInvalid);
}
