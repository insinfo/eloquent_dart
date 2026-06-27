import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 4 / iso-8859-4 codec for easy encoding and decoding.
class Latin4Codec extends dart_convert.Encoding {
  /// Creates a new [Latin4Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin4Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin4Decoder get decoder => allowInvalid
      ? const Latin4Decoder(allowInvalid: true)
      : const Latin4Decoder(allowInvalid: false);

  @override
  Latin4Encoder get encoder => allowInvalid
      ? const Latin4Encoder(allowInvalid: true)
      : const Latin4Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-4';
}

/// Encodes texts into latin 4 / iso-8859-4 data
class Latin4Encoder extends LatinEncoder {
  /// Creates a new [Latin4Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin4Encoder({
    bool allowInvalid = false,
  }) : super(_latin4SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 4 /  iso-8859-4 data.
class Latin4Decoder extends LatinDecoder {
  /// Creates a new [Latin4Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin4Decoder({
    bool allowInvalid = false,
  }) : super(_latin4Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin4Symbols =
// ignore: lines_longer_than_80_chars
    'ĄĸŖ¤ĨĻ§¨ŠĒĢŦ\u{00AD}Ž¯°ą˛ŗ´ĩļˇ¸šēģŧŊžŋĀÁÂÃÄÅÆĮČÉĘËĖÍÎĪĐŅŌĶÔÕÖ×ØŲÚÛÜŨŪßāáâãäåæįčéęëėíîīđņōķôõö÷øųúûüũū˙';
const Map<int, int> _latin4SymbolMap = {
  260: 161,
  312: 162,
  342: 163,
  164: 164,
  296: 165,
  315: 166,
  167: 167,
  168: 168,
  352: 169,
  274: 170,
  290: 171,
  358: 172,
  173: 173,
  381: 174,
  175: 175,
  176: 176,
  261: 177,
  731: 178,
  343: 179,
  180: 180,
  297: 181,
  316: 182,
  711: 183,
  184: 184,
  353: 185,
  275: 186,
  291: 187,
  359: 188,
  330: 189,
  382: 190,
  331: 191,
  256: 192,
  193: 193,
  194: 194,
  195: 195,
  196: 196,
  197: 197,
  198: 198,
  302: 199,
  268: 200,
  201: 201,
  280: 202,
  203: 203,
  278: 204,
  205: 205,
  206: 206,
  298: 207,
  272: 208,
  325: 209,
  332: 210,
  310: 211,
  212: 212,
  213: 213,
  214: 214,
  215: 215,
  216: 216,
  370: 217,
  218: 218,
  219: 219,
  220: 220,
  360: 221,
  362: 222,
  223: 223,
  257: 224,
  225: 225,
  226: 226,
  227: 227,
  228: 228,
  229: 229,
  230: 230,
  303: 231,
  269: 232,
  233: 233,
  281: 234,
  235: 235,
  279: 236,
  237: 237,
  238: 238,
  299: 239,
  273: 240,
  326: 241,
  333: 242,
  311: 243,
  244: 244,
  245: 245,
  246: 246,
  247: 247,
  248: 248,
  371: 249,
  250: 250,
  251: 251,
  252: 252,
  361: 253,
  363: 254,
  729: 255,
};
