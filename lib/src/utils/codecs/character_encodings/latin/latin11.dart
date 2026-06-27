import 'dart:convert' as dart_convert;

import 'latin.dart';

/// Provides a latin 11 / iso-8859-11 codec for easy encoding and decoding.
class Latin11Codec extends dart_convert.Encoding {
  /// Creates a new [Latin11Codec]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ? and decoded to �
  const Latin11Codec({
    this.allowInvalid = false,
  });

  /// Should invalid character codes be ignored?
  ///
  /// When `false`, an invalid character code
  /// will throw [FormatException].
  final bool allowInvalid;

  @override
  Latin11Decoder get decoder => allowInvalid
      ? const Latin11Decoder(allowInvalid: true)
      : const Latin11Decoder(allowInvalid: false);

  @override
  Latin11Encoder get encoder => allowInvalid
      ? const Latin11Encoder(allowInvalid: true)
      : const Latin11Encoder(allowInvalid: false);

  @override
  String get name => 'iso-8859-11';
}

/// Encodes texts into latin 11 / iso-88511-11 data
class Latin11Encoder extends LatinEncoder {
  /// Creates a new [Latin11Encoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be encoded to ?
  const Latin11Encoder({
    bool allowInvalid = false,
  }) : super(_latin11SymbolMap, allowInvalid: allowInvalid);
}

/// Decodes latin 11 /  iso-88511-11 data.
class Latin11Decoder extends LatinDecoder {
  /// Creates a new [Latin11Decoder]
  ///
  /// Set [allowInvalid] to `true` for ignoring invalid data.
  /// When invalid data is allowed it  will be decoded to �
  const Latin11Decoder({
    bool allowInvalid = false,
  }) : super(_latin11Symbols, allowInvalid: allowInvalid);
}

// cSpell:disable
const String _latin11Symbols =
// ignore: lines_longer_than_80_chars
    'กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรฤลฦวศษสหฬอฮฯะัาำิีึืฺุู????฿เแโใไๅๆ็่้๊๋์ํ๎๏๐๑๒๓๔๕๖๗๘๙๚๛????';
const Map<int, int> _latin11SymbolMap = {
  3585: 161,
  3586: 162,
  3587: 163,
  3588: 164,
  3589: 165,
  3590: 166,
  3591: 167,
  3592: 168,
  3593: 169,
  3594: 170,
  3595: 171,
  3596: 172,
  3597: 173,
  3598: 174,
  3599: 175,
  3600: 176,
  3601: 177,
  3602: 178,
  3603: 179,
  3604: 180,
  3605: 181,
  3606: 182,
  3607: 183,
  3608: 184,
  3609: 185,
  3610: 186,
  3611: 187,
  3612: 188,
  3613: 189,
  3614: 190,
  3615: 191,
  3616: 192,
  3617: 193,
  3618: 194,
  3619: 195,
  3620: 196,
  3621: 197,
  3622: 198,
  3623: 199,
  3624: 200,
  3625: 201,
  3626: 202,
  3627: 203,
  3628: 204,
  3629: 205,
  3630: 206,
  3631: 207,
  3632: 208,
  3633: 209,
  3634: 210,
  3635: 211,
  3636: 212,
  3637: 213,
  3638: 214,
  3639: 215,
  3640: 216,
  3641: 217,
  3642: 218,
  3647: 223,
  3648: 224,
  3649: 225,
  3650: 226,
  3651: 227,
  3652: 228,
  3653: 229,
  3654: 230,
  3655: 231,
  3656: 232,
  3657: 233,
  3658: 234,
  3659: 235,
  3660: 236,
  3661: 237,
  3662: 238,
  3663: 239,
  3664: 240,
  3665: 241,
  3666: 242,
  3667: 243,
  3668: 244,
  3669: 245,
  3670: 246,
  3671: 247,
  3672: 248,
  3673: 249,
  3674: 250,
  3675: 251,
};
