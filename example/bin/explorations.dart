// ignore_for_file: dead_code

import 'dart:io';

import 'package:eloquent/eloquent.dart';
//nano mytimezone
//zic -d /usr/share/zoneinfo/ mytimezone
//cd /usr/share/zoneinfo/
//nano /usr/share/zoneinfo/America/Sao_Paulo
// cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
// zdump -v America/Sao_Paulo
//apt install --reinstall tzdata

class CustomDateTime {
  int year = DateTime.now().year;
  int month = 1;
  int day = 1;
  int hour = 0;
  int minute = 0;
  int second = 0;
  int millisecond = 0;
  int microsecond = 0;
  double offsetHours = 0.0;

  CustomDateTime(this.year,
      [this.month = 1,
      this.day = 1,
      this.hour = 0,
      this.minute = 0,
      this.second = 0,
      this.millisecond = 0,
      this.microsecond = 0,
      this.offsetHours = 0]);

  CustomDateTime.now({this.offsetHours = 0}) {
    final now = DateTime.now().toUtc();
    final adjusted = now.add(Duration(
        hours: offsetHours.floor(),
        minutes: ((offsetHours - offsetHours.floor()) * 60).round()));
    year = adjusted.year;
    month = adjusted.month;
    day = adjusted.day;
    hour = adjusted.hour;
    minute = adjusted.minute;
    second = adjusted.second;
    millisecond = adjusted.millisecond;
    microsecond = adjusted.microsecond;
  }

  @override
  String toString() {
    int offsetHour = offsetHours.floor();
    int offsetMinute = ((offsetHours - offsetHour) * 60).round();
    String offsetSign = offsetHours < 0 ? '-' : '+';
    return '$year-${_twoDigits(month)}-${_twoDigits(day)} ${_twoDigits(hour)}:${_twoDigits(minute)}:${_twoDigits(second)}.${_threeDigits(millisecond)}${_threeDigits(microsecond)} (UTC$offsetSign${_twoDigits(offsetHour.abs())}:${_twoDigits(offsetMinute.abs())})';
  }

  String toIso8601String() {
    int offsetHour = offsetHours.floor();
    int offsetMinute = ((offsetHours - offsetHour) * 60).round();
    String offsetSign = offsetHours < 0 ? '-' : '+';
    return '$year-${_twoDigits(month)}-${_twoDigits(day)}T${_twoDigits(hour)}:${_twoDigits(minute)}:${_twoDigits(second)}.${_threeDigits(millisecond)}${_threeDigits(microsecond)}Z$offsetSign${_twoDigits(offsetHour.abs())}:${_twoDigits(offsetMinute.abs())}';
  }

  String _twoDigits(int n) {
    if (n >= 10) return "$n";
    return "0$n";
  }

  String _threeDigits(int n) {
    if (n >= 100) return "$n";
    if (n >= 10) return "0$n";
    return "00$n";
  }

  CustomDateTime add(Duration duration) {
    DateTime utcDateTime = DateTime(
            year, month, day, hour, minute, second, millisecond, microsecond)
        .toUtc();
    DateTime newDateTime = utcDateTime.add(duration).toUtc();
    return CustomDateTime(
      newDateTime.year,
      newDateTime.month,
      newDateTime.day,
      newDateTime.hour,
      newDateTime.minute,
      newDateTime.second,
      newDateTime.millisecond,
      newDateTime.microsecond,
      offsetHours,
    );
  }

  CustomDateTime subtract(Duration duration) {
    return add(-duration);
  }

  Duration difference(CustomDateTime other) {
    DateTime thisDateTime = DateTime(
            year, month, day, hour, minute, second, millisecond, microsecond)
        .toUtc();
    DateTime otherDateTime = DateTime(
            other.year,
            other.month,
            other.day,
            other.hour,
            other.minute,
            other.second,
            other.millisecond,
            other.microsecond)
        .toUtc();
    return thisDateTime.difference(otherDateTime);
  }

  bool isBefore(CustomDateTime other) {
    DateTime thisDateTime = DateTime(
            year, month, day, hour, minute, second, millisecond, microsecond)
        .toUtc();
    DateTime otherDateTime = DateTime(
            other.year,
            other.month,
            other.day,
            other.hour,
            other.minute,
            other.second,
            other.millisecond,
            other.microsecond)
        .toUtc();
    return thisDateTime.isBefore(otherDateTime);
  }

  bool isAfter(CustomDateTime other) {
    return !isBefore(other) && !isAtSameMomentAs(other);
  }

  bool isAtSameMomentAs(CustomDateTime other) {
    return !isBefore(other) && !isAfter(other);
  }

  int compareTo(CustomDateTime other) {
    DateTime thisDateTime = DateTime(
            year, month, day, hour, minute, second, millisecond, microsecond)
        .toUtc();
    DateTime otherDateTime = DateTime(
            other.year,
            other.month,
            other.day,
            other.hour,
            other.minute,
            other.second,
            other.millisecond,
            other.microsecond)
        .toUtc();
    return thisDateTime.compareTo(otherDateTime);
  }
}

void main3() {
  CustomDateTime customDateTime =
      CustomDateTime(2024, 7, 25, 17, 00, 0, 0, 0, -3.5);
  print('customDateTime $customDateTime');

  CustomDateTime customNow = CustomDateTime.now(offsetHours: -3.5);
  print(customNow);

  // Adicionando e subtraindo duração
  CustomDateTime addedDateTime =
      customDateTime.add(Duration(hours: 5, minutes: 30));
  print(addedDateTime);

  CustomDateTime subtractedDateTime =
      customDateTime.subtract(Duration(hours: 2, minutes: 15));
  print(subtractedDateTime);

  // Comparando datas
  print(customDateTime.isBefore(customNow));
  print(customDateTime.isAfter(customNow));
  print(customDateTime.isAtSameMomentAs(customNow));
  print(customDateTime.compareTo(customNow));
}

extension DateTimeExtension on DateTime {
  DateTime asLocal() {
    ///return DateTime(year,month, day, hour, minute, second, millisecond, microsecond);
    final now = DateTime.now();
    final timeZoneOffset = now.timeZoneOffset;
    //  dt.copyWith(
    //     year: year,
    //     month: month,
    //     day: day,
    //     hour: hour,
    //     minute: minute,
    //     second: second,
    //     millisecond: millisecond,
    //     microsecond: microsecond);
    return add(timeZoneOffset);
  }
}

void main(List<String> args) async {
  //774702600000000 = 2024-07-19 11:10:00 = DateTime(2024, 07, 19, 11, 10, 00)
  final dur = Duration(microseconds: 774702600000000);
  final dtUtc = DateTime.utc(2000).add(dur);

  final nowDt = DateTime.now();
  var baseDt = DateTime(2000);
 
  if (baseDt.timeZoneOffset != nowDt.timeZoneOffset) {    
    final difference = baseDt.timeZoneOffset - nowDt.timeZoneOffset;       
    baseDt = baseDt.add(difference);     
  }
  final dtLocalDecode = baseDt.add(dur);

  final dartDt = DateTime(2000, 1, 1, 0, 0, 0, 0, 0);

  print('dtUtc $dtUtc ${dtUtc.timeZoneOffset}  ${dtUtc.timeZoneName}');

  print(
      'dtLocal decode $dtLocalDecode ${dtLocalDecode.timeZoneOffset}  ${dtLocalDecode.timeZoneName}');

  print('dartDt  $dartDt ${dartDt.timeZoneOffset}  ${dartDt.timeZoneName}');

  print('dartNow  $nowDt ${nowDt.timeZoneOffset}  ${nowDt.timeZoneName}');
  return;

  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres', // postgres | dargres | postgres_v3
    'timezone': 'America/Sao_Paulo',
    'forceDecodeTimestamptzAsUTC': false,
    'forceDecodeTimestampAsUTC': false,
    'forceDecodeDateAsUTC': false,
    'pool': true,
    'poolsize': 2,
    'host': 'localhost',
    'port': '5435',
    'database': 'sistemas',
    'username': 'dart',
    'password': 'dart',
    'charset': 'win1252',
    'prefix': '',
    'schema': ['public'],
    //'sslmode' : 'require',
  });

  manager.setAsGlobal();

  final connection = await manager.connection();

  // var results =
  //     await connection.select("select current_timestamp, current_date ");
  // print('results: ${results}');
  // var currentTimestamp = results.first['current_timestamp'] as DateTime;
  // print('dafault: $currentTimestamp ${currentTimestamp.timeZoneName}');
  // print('local: ${currentTimestamp.toLocal()}');

//  final id = await connection.table('sigep.inscricoes').insertGetId({
//     'titulo': 'teste',
//     'anoExercicio': 2024,
//     'dataInicial': DateTime(2024, 07, 19, 11, 10, 00),
//     'dataFinal': DateTime(2024, 07, 19, 11, 10, 00),
//   });

  final result =
      await connection.table('sigep.inscricoes').where('id', '=', 21).first();
  print('result ${result}');

  // await connection.execute("set timezone to 'America/Sao_Paulo'");
  // results = await connection.execute("select current_timestamp");
  // currentTimestamp = results.first.first as DateTime;
  // print(
  //     'America/Sao_Paulo: $currentTimestamp ${currentTimestamp.timeZoneName}');

  // final res = await db.transaction((ctx) async {
  //   await ctx.table('test_table').insert({'id':10,'name':'Jane Doe'});
  //   final res = await ctx.table('test_table').limit(2).get();
  //   return res;
  // });
  // print('res $res');

  exit(0);
}
