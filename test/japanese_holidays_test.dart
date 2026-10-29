import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/japanese_holidays.dart';

void main() {
  test('the holiday law starts on 20 July 1948', () {
    expect(japaneseHolidayName(DateTime(1947, 11, 3)), isNull);
    expect(japaneseHolidayName(DateTime(1948, 1, 1)), isNull);
    expect(japaneseHolidayName(DateTime(1948, 5, 3)), isNull);
    expect(japaneseHolidayName(DateTime(1948, 9, 23)), '秋分の日');
    expect(japaneseHolidayName(DateTime(1948, 11, 3)), '文化の日');
    expect(japaneseHolidayName(DateTime(1949, 1, 1)), '元日');
  });

  test(
    'substitute holiday rules respect their historical start and changes',
    () {
      expect(japaneseHolidayName(DateTime(1973, 2, 12)), isNull);
      expect(japaneseHolidayName(DateTime(1973, 4, 30)), '振替休日');
      expect(japaneseHolidayName(DateTime(1998, 5, 4)), '振替休日');
      expect(japaneseHolidayName(DateTime(1998, 5, 6)), isNull);
      expect(japaneseHolidayName(DateTime(2009, 5, 6)), '振替休日');
      expect(japaneseHolidayName(DateTime(2026, 5, 6)), '振替休日');
    },
  );

  test('citizen holidays and imperial occasions match LiveStair names', () {
    expect(japaneseHolidayName(DateTime(2015, 9, 22)), '休日');
    expect(japaneseHolidayName(DateTime(2026, 9, 22)), '休日');
    expect(japaneseHolidayName(DateTime(2019, 4, 30)), '休日');
    expect(japaneseHolidayName(DateTime(2019, 5, 1)), '休日（祝日扱い）');
    expect(japaneseHolidayName(DateTime(2019, 5, 2)), '休日');
    expect(japaneseHolidayName(DateTime(2019, 10, 22)), '休日（祝日扱い）');
    expect(japaneseHolidayName(DateTime(1959, 4, 10)), '結婚の儀');
  });

  test('Olympic exceptions replace the normal dates in 2020 and 2021', () {
    expect(japaneseHolidayName(DateTime(2020, 7, 23)), '海の日');
    expect(japaneseHolidayName(DateTime(2020, 7, 24)), 'スポーツの日');
    expect(japaneseHolidayName(DateTime(2020, 8, 10)), '山の日');
    expect(japaneseHolidayName(DateTime(2020, 10, 12)), isNull);
    expect(japaneseHolidayName(DateTime(2021, 7, 22)), '海の日');
    expect(japaneseHolidayName(DateTime(2021, 7, 23)), 'スポーツの日');
    expect(japaneseHolidayName(DateTime(2021, 8, 8)), '山の日');
    expect(japaneseHolidayName(DateTime(2021, 8, 9)), '振替休日');
    expect(japaneseHolidayName(DateTime(2021, 8, 11)), isNull);
  });

  test('equinox calculations retain truncation rules before 1980', () {
    expect(japaneseHolidayName(DateTime(1955, 3, 21)), '春分の日');
    expect(japaneseHolidayName(DateTime(1979, 3, 21)), '春分の日');
    expect(japaneseHolidayName(DateTime(1980, 3, 20)), '春分の日');
    expect(japaneseHolidayName(DateTime(2026, 3, 20)), '春分の日');
    expect(japaneseHolidayName(DateTime(2026, 9, 23)), '秋分の日');
    expect(japaneseHolidayName(DateTime(2100, 3, 20)), '春分の日');
  });

  test(
    'holiday lookup uses the calendar day, without treating weekends as holidays',
    () {
      expect(japaneseHolidayName(DateTime(2026, 11, 3, 23, 55)), '文化の日');
      expect(japaneseHolidayName(DateTime(2026, 10, 31)), isNull);
      expect(isJapaneseHoliday(DateTime(2026, 11, 3)), isTrue);
      expect(isJapaneseHoliday(DateTime(2026, 10, 31)), isFalse);
    },
  );
}
