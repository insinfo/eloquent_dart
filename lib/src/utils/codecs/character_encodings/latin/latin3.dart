import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 3 / iso-8859-3 codec for easy encoding and decoding.
class Latin3Codec extends dart_convert.Encoding {
  /// Creates a new [Latin3Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin3Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin3Decoder get decoder => allowInvalid
      ? const Latin3Decoder(allowInvalid: true)
      : const Latin3Decoder(allowInvalid: false);

  @override
  Latin3Encoder get encoder => allowInvalid
      ? const Latin3Encoder(allowInvalid: true)
      : const Latin3Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-3';
}

/// Encodes texts into latin 3 / iso-8859-3 data
class Latin3Encoder extends LatinEncoder {
  /// Creates a new [Latin3Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin3Encoder({
    bool allowInvalid = false,
  }) : super(_latin3SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 3 /  iso-8859-3 data.
class Latin3Decoder extends LatinDecoder {
  /// Creates a new [Latin3Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin3Decoder({
    bool allowInvalid = false,
  }) : super(_latin3Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin3Symbols =
// ignore: lines_longer_than_80_chars
    'Ħ˘£¤?Ĥ§¨İŞĞĴ\u{00AD}?Ż°ħ²³´µĥ·¸ışğĵ½?żÀÁÂ?ÄĊĈÇÈÉÊËÌÍÎÏ?ÑÒÓÔĠÖ×ĜÙÚÛÜŬŜßàáâ?äċĉçèéêëìíîï?ñòóôġö÷ĝùúûüŭŝ˙';
const Map<int, int> _latin3SymbolMap = {
  294: 161,
  728: 162,
  163: 163,
  164: 164,
  292: 166,
  167: 167,
  168: 168,
  304: 169,
  350: 170,
  286: 171,
  308: 172,
  173: 173,
  379: 175,
  176: 176,
  295: 177,
  178: 178,
  179: 179,
  180: 180,
  181: 181,
  293: 182,
  183: 183,
  184: 184,
  305: 185,
  351: 186,
  287: 187,
  309: 188,
  189: 189,
  380: 191,
  192: 192,
  193: 193,
  194: 194,
  196: 196,
  266: 197,
  264: 198,
  199: 199,
  200: 200,
  201: 201,
  202: 202,
  203: 203,
  204: 204,
  205: 205,
  206: 206,
  207: 207,
  209: 209,
  210: 210,
  211: 211,
  212: 212,
  288: 213,
  214: 214,
  215: 215,
  284: 216,
  217: 217,
  218: 218,
  219: 219,
  220: 220,
  364: 221,
  348: 222,
  223: 223,
  224: 224,
  225: 225,
  226: 226,
  228: 228,
  267: 229,
  265: 230,
  231: 231,
  232: 232,
  233: 233,
  234: 234,
  235: 235,
  236: 236,
  237: 237,
  238: 238,
  239: 239,
  241: 241,
  242: 242,
  243: 243,
  244: 244,
  289: 245,
  246: 246,
  247: 247,
  285: 248,
  249: 249,
  250: 250,
  251: 251,
  252: 252,
  365: 253,
  349: 254,
  729: 255,
};
