import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 5 / iso-8859-5 codec for easy encoding and decoding.
class Latin5Codec extends dart_convert.Encoding {
  /// Creates a new [Latin5Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin5Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin5Decoder get decoder => allowInvalid
      ? const Latin5Decoder(allowInvalid: true)
      : const Latin5Decoder(allowInvalid: false);

  @override
  Latin5Encoder get encoder => allowInvalid
      ? const Latin5Encoder(allowInvalid: true)
      : const Latin5Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-5';
}

/// Encodes texts into latin 5 / iso-8859-5 data
class Latin5Encoder extends LatinEncoder {
  /// Creates a new [Latin5Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin5Encoder({
    bool allowInvalid = false,
  }) : super(_latin5SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 5 /  iso-8859-5 data.
class Latin5Decoder extends LatinDecoder {
  /// Creates a new [Latin5Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin5Decoder({
    bool allowInvalid = false,
  }) : super(_latin5Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin5Symbols =
// ignore: lines_longer_than_80_chars
    'ЁЂЃЄЅІЇЈЉЊЋЌ\u{00AD}ЎЏАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя№ёђѓєѕіїјљњћќ§ўџ';
const Map<int, int> _latin5SymbolMap = {
  1025: 161,
  1026: 162,
  1027: 163,
  1028: 164,
  1029: 165,
  1030: 166,
  1031: 167,
  1032: 168,
  1033: 169,
  1034: 170,
  1035: 171,
  1036: 172,
  173: 173,
  1038: 174,
  1039: 175,
  1040: 176,
  1041: 177,
  1042: 178,
  1043: 179,
  1044: 180,
  1045: 181,
  1046: 182,
  1047: 183,
  1048: 184,
  1049: 185,
  1050: 186,
  1051: 187,
  1052: 188,
  1053: 189,
  1054: 190,
  1055: 191,
  1056: 192,
  1057: 193,
  1058: 194,
  1059: 195,
  1060: 196,
  1061: 197,
  1062: 198,
  1063: 199,
  1064: 200,
  1065: 201,
  1066: 202,
  1067: 203,
  1068: 204,
  1069: 205,
  1070: 206,
  1071: 207,
  1072: 208,
  1073: 209,
  1074: 210,
  1075: 211,
  1076: 212,
  1077: 213,
  1078: 214,
  1079: 215,
  1080: 216,
  1081: 217,
  1082: 218,
  1083: 219,
  1084: 220,
  1085: 221,
  1086: 222,
  1087: 223,
  1088: 224,
  1089: 225,
  1090: 226,
  1091: 227,
  1092: 228,
  1093: 229,
  1094: 230,
  1095: 231,
  1096: 232,
  1097: 233,
  1098: 234,
  1099: 235,
  1100: 236,
  1101: 237,
  1102: 238,
  1103: 239,
  8470: 240,
  1105: 241,
  1106: 242,
  1107: 243,
  1108: 244,
  1109: 245,
  1110: 246,
  1111: 247,
  1112: 248,
  1113: 249,
  1114: 250,
  1115: 251,
  1116: 252,
  167: 253,
  1118: 254,
  1119: 255,
};
