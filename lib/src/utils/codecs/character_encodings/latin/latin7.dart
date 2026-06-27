import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 7 / iso-8859-7 codec for easy encoding and decoding.
class Latin7Codec extends dart_convert.Encoding {
  /// Creates a new [Latin7Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin7Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin7Decoder get decoder => allowInvalid
      ? const Latin7Decoder(allowInvalid: true)
      : const Latin7Decoder(allowInvalid: false);

  @override
  Latin7Encoder get encoder => allowInvalid
      ? const Latin7Encoder(allowInvalid: true)
      : const Latin7Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-7';
}

/// Encodes texts into latin 7 / iso-8859-7 data
class Latin7Encoder extends LatinEncoder {
  /// Creates a new [Latin7Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin7Encoder({
    bool allowInvalid = false,
  }) : super(_latin7SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 7 /  iso-8859-7 data.
class Latin7Decoder extends LatinDecoder {
  /// Creates a new [Latin7Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin7Decoder({
    bool allowInvalid = false,
  }) : super(_latin7Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin7Symbols =
// ignore: lines_longer_than_80_chars
    '‘’£€₯¦§¨©ͺ«¬\u{00AD}?―°±²³΄΅Ά·ΈΉΊ»Ό½ΎΏΐΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡ?ΣΤΥΦΧΨΩΪΫάέήίΰαβγδεζηθικλμνξοπρςστυφχψωϊϋόύώ?';
const Map<int, int> _latin7SymbolMap = {
  8216: 161,
  8217: 162,
  163: 163,
  8364: 164,
  8367: 165,
  166: 166,
  167: 167,
  168: 168,
  169: 169,
  890: 170,
  171: 171,
  172: 172,
  173: 173,
  8213: 175,
  176: 176,
  177: 177,
  178: 178,
  179: 179,
  900: 180,
  901: 181,
  902: 182,
  183: 183,
  904: 184,
  905: 185,
  906: 186,
  187: 187,
  908: 188,
  189: 189,
  910: 190,
  911: 191,
  912: 192,
  913: 193,
  914: 194,
  915: 195,
  916: 196,
  917: 197,
  918: 198,
  919: 199,
  920: 200,
  921: 201,
  922: 202,
  923: 203,
  924: 204,
  925: 205,
  926: 206,
  927: 207,
  928: 208,
  929: 209,
  931: 211,
  932: 212,
  933: 213,
  934: 214,
  935: 215,
  936: 216,
  937: 217,
  938: 218,
  939: 219,
  940: 220,
  941: 221,
  942: 222,
  943: 223,
  944: 224,
  945: 225,
  946: 226,
  947: 227,
  948: 228,
  949: 229,
  950: 230,
  951: 231,
  952: 232,
  953: 233,
  954: 234,
  955: 235,
  956: 236,
  957: 237,
  958: 238,
  959: 239,
  960: 240,
  961: 241,
  962: 242,
  963: 243,
  964: 244,
  965: 245,
  966: 246,
  967: 247,
  968: 248,
  969: 249,
  970: 250,
  971: 251,
  972: 252,
  973: 253,
  974: 254,
};
