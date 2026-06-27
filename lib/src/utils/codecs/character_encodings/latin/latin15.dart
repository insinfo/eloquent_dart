import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 15 / iso-8859-15 codec for easy encoding and decoding.
class Latin15Codec extends dart_convert.Encoding {
  /// Creates a new [Latin15Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin15Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin15Decoder get decoder => allowInvalid
      ? const Latin15Decoder(allowInvalid: true)
      : const Latin15Decoder(allowInvalid: false);

  @override
  Latin15Encoder get encoder => allowInvalid
      ? const Latin15Encoder(allowInvalid: true)
      : const Latin15Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-15';
}

/// Encodes texts into latin 15 / iso-88515-15 data
class Latin15Encoder extends LatinEncoder {
  /// Creates a new [Latin15Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin15Encoder({
    bool allowInvalid = false,
  }) : super(_latin15SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 15 /  iso-88515-15 data.
class Latin15Decoder extends LatinDecoder {
  /// Creates a new [LatinDecoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin15Decoder({
    bool allowInvalid = false,
  }) : super(_latin15Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin15Symbols =
// ignore: lines_longer_than_80_chars
    '¡¢£€¥Š§š©ª«¬\u{00AD}®¯°±²³Žµ¶·ž¹º»ŒœŸ¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ';
const Map<int, int> _latin15SymbolMap = {
  161: 161,
  162: 162,
  163: 163,
  8364: 164,
  165: 165,
  352: 166,
  167: 167,
  353: 168,
  169: 169,
  170: 170,
  171: 171,
  172: 172,
  173: 173,
  174: 174,
  175: 175,
  176: 176,
  177: 177,
  178: 178,
  179: 179,
  381: 180,
  181: 181,
  182: 182,
  183: 183,
  382: 184,
  185: 185,
  186: 186,
  187: 187,
  338: 188,
  339: 189,
  376: 190,
  191: 191,
  192: 192,
  193: 193,
  194: 194,
  195: 195,
  196: 196,
  197: 197,
  198: 198,
  199: 199,
  200: 200,
  201: 201,
  202: 202,
  203: 203,
  204: 204,
  205: 205,
  206: 206,
  207: 207,
  208: 208,
  209: 209,
  210: 210,
  211: 211,
  212: 212,
  213: 213,
  214: 214,
  215: 215,
  216: 216,
  217: 217,
  218: 218,
  219: 219,
  220: 220,
  221: 221,
  222: 222,
  223: 223,
  224: 224,
  225: 225,
  226: 226,
  227: 227,
  228: 228,
  229: 229,
  230: 230,
  231: 231,
  232: 232,
  233: 233,
  234: 234,
  235: 235,
  236: 236,
  237: 237,
  238: 238,
  239: 239,
  240: 240,
  241: 241,
  242: 242,
  243: 243,
  244: 244,
  245: 245,
  246: 246,
  247: 247,
  248: 248,
  249: 249,
  250: 250,
  251: 251,
  252: 252,
  253: 253,
  254: 254,
  255: 255,
};
