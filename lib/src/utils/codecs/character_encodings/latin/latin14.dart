import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 14 / iso-8859-14 codec for easy encoding and decoding.
class Latin14Codec extends dart_convert.Encoding {
  /// Creates a new [Latin14Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin14Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin14Decoder get decoder => allowInvalid
      ? const Latin14Decoder(allowInvalid: true)
      : const Latin14Decoder(allowInvalid: false);

  @override
  Latin14Encoder get encoder => allowInvalid
      ? const Latin14Encoder(allowInvalid: true)
      : const Latin14Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-14';
}

/// Encodes texts into latin 14 / iso-88514-14 data
class Latin14Encoder extends LatinEncoder {
  /// Creates a new [Latin14Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin14Encoder({
    bool allowInvalid = false,
  }) : super(_latin14SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 14 /  iso-88514-14 data.
class Latin14Decoder extends LatinDecoder {
  /// Creates a new [Latin14Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin14Decoder({
    bool allowInvalid = false,
  }) : super(_latin14Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin14Symbols =
// ignore: lines_longer_than_80_chars
    'Ḃḃ£ĊċḊ§Ẁ©ẂḋỲ\u{00AD}®ŸḞḟĠġṀṁ¶ṖẁṗẃṠỳẄẅṡÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏŴÑÒÓÔÕÖṪØÙÚÛÜÝŶßàáâãäåæçèéêëìíîïŵñòóôõöṫøùúûüýŷÿ';
const Map<int, int> _latin14SymbolMap = {
  7682: 161,
  7683: 162,
  163: 163,
  266: 164,
  267: 165,
  7690: 166,
  167: 167,
  7808: 168,
  169: 169,
  7810: 170,
  7691: 171,
  7922: 172,
  173: 173,
  174: 174,
  376: 175,
  7710: 176,
  7711: 177,
  288: 178,
  289: 179,
  7744: 180,
  7745: 181,
  182: 182,
  7766: 183,
  7809: 184,
  7767: 185,
  7811: 186,
  7776: 187,
  7923: 188,
  7812: 189,
  7813: 190,
  7777: 191,
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
  372: 208,
  209: 209,
  210: 210,
  211: 211,
  212: 212,
  213: 213,
  214: 214,
  7786: 215,
  216: 216,
  217: 217,
  218: 218,
  219: 219,
  220: 220,
  221: 221,
  374: 222,
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
  373: 240,
  241: 241,
  242: 242,
  243: 243,
  244: 244,
  245: 245,
  246: 246,
  7787: 247,
  248: 248,
  249: 249,
  250: 250,
  251: 251,
  252: 252,
  253: 253,
  375: 254,
  255: 255,
};
