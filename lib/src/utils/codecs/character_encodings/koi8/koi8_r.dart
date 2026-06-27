import 'dart:convert' as dart_convert;

import 'koi8.dart';

/// A codec for the KOI8-r encoding
class Koi8rCodec extends dart_convert.Encoding {
  /// Creates a new [Koi8rCodec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Koi8rCodec({this.allowInvalid = false});

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Koi8rDecoder get decoder => allowInvalid
      ? const Koi8rDecoder(allowInvalid: true)
      : const Koi8rDecoder(allowInvalid: false);

  @override
  // NOTE: implement encoder
  Koi8rEncoder get encoder => allowInvalid
      ? const Koi8rEncoder(allowInvalid: true)
      : const Koi8rEncoder(allowInvalid: false);

  @override
  String get name => 'KOI8-R';
}

/// The KOI8-r compatible encoder
class Koi8rEncoder extends KoiEncoder {
  /// Creates a new [Koi8rEncoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Koi8rEncoder({
    bool allowInvalid = false,
  }) : super(_koi8rSymbolMap, allowInvalid: allowInvalid);
}

/// A KOI8-r compatible decoder
class Koi8rDecoder extends KoiDecoder {
  /// Creates a new [KoiDecoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Koi8rDecoder({
    bool allowInvalid = false,
  }) : super(_koi8rSymbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _koi8rSymbols =
// ignore: lines_longer_than_80_chars
    '─│┌┐└┘├┤┬┴┼▀▄█▌▐░▒▓⌠■∙√≈≤≥\u{00A0}⌡°²·÷═║╒ё╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡Ё╢╣╤╥╦╧╨╩╪╫╬©юабцдефгхийклмнопярстужвьызшэщчъЮАБЦДЕФГХИЙКЛМНОПЯРСТУЖВЬЫЗШЭЩЧЪ';

const Map<int, int> _koi8rSymbolMap = {
  9472: 128,
  9474: 129,
  9484: 130,
  9488: 131,
  9492: 132,
  9496: 133,
  9500: 134,
  9508: 135,
  9516: 136,
  9524: 137,
  9532: 138,
  9600: 139,
  9604: 140,
  9608: 141,
  9612: 142,
  9616: 143,
  9617: 144,
  9618: 145,
  9619: 146,
  8992: 147,
  9632: 148,
  8729: 149,
  8730: 150,
  8776: 151,
  8804: 152,
  8805: 153,
  160: 154,
  8993: 155,
  176: 156,
  178: 157,
  183: 158,
  247: 159,
  9552: 160,
  9553: 161,
  9554: 162,
  1105: 163,
  9555: 164,
  9556: 165,
  9557: 166,
  9558: 167,
  9559: 168,
  9560: 169,
  9561: 170,
  9562: 171,
  9563: 172,
  9564: 173,
  9565: 174,
  9566: 175,
  9567: 176,
  9568: 177,
  9569: 178,
  1025: 179,
  9570: 180,
  9571: 181,
  9572: 182,
  9573: 183,
  9574: 184,
  9575: 185,
  9576: 186,
  9577: 187,
  9578: 188,
  9579: 189,
  9580: 190,
  169: 191,
  1102: 192,
  1072: 193,
  1073: 194,
  1094: 195,
  1076: 196,
  1077: 197,
  1092: 198,
  1075: 199,
  1093: 200,
  1080: 201,
  1081: 202,
  1082: 203,
  1083: 204,
  1084: 205,
  1085: 206,
  1086: 207,
  1087: 208,
  1103: 209,
  1088: 210,
  1089: 211,
  1090: 212,
  1091: 213,
  1078: 214,
  1074: 215,
  1100: 216,
  1099: 217,
  1079: 218,
  1096: 219,
  1101: 220,
  1097: 221,
  1095: 222,
  1098: 223,
  1070: 224,
  1040: 225,
  1041: 226,
  1062: 227,
  1044: 228,
  1045: 229,
  1060: 230,
  1043: 231,
  1061: 232,
  1048: 233,
  1049: 234,
  1050: 235,
  1051: 236,
  1052: 237,
  1053: 238,
  1054: 239,
  1055: 240,
  1071: 241,
  1056: 242,
  1057: 243,
  1058: 244,
  1059: 245,
  1046: 246,
  1042: 247,
  1068: 248,
  1067: 249,
  1047: 250,
  1064: 251,
  1069: 252,
  1065: 253,
  1063: 254,
  1066: 255
};
