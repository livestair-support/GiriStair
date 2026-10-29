/// Port of LiveStair JapaneseHolidays.swift (8431bb5). No network dependency.
library;

final Map<int, Map<DateTime, String>> _cache = {};

String? japaneseHolidayName(DateTime date) =>
    _holidays(date.year)[DateTime.utc(date.year, date.month, date.day)];

bool isJapaneseHoliday(DateTime date) => japaneseHolidayName(date) != null;

Map<DateTime, String> _holidays(int year) => _cache.putIfAbsent(year, () {
  if (year < 1948) return {};
  final national = <DateTime, String>{};
  void add(int month, int day, String name) {
    final date = DateTime.utc(year, month, day);
    if (year == 1948 && date.isBefore(DateTime.utc(1948, 7, 20))) return;
    national[date] = name;
  }

  int monday(int month, int nth) =>
      1 +
      (DateTime.monday - DateTime.utc(year, month, 1).weekday + 7) % 7 +
      (nth - 1) * 7;
  int equinox(bool spring) {
    final base = year <= 1979
        ? spring
              ? 20.8357
              : 23.2588
        : year <= 2099
        ? spring
              ? 20.8431
              : 23.2488
        : spring
        ? 21.8510
        : 24.2488;
    final leap = (year - (year <= 1979 ? 1983 : 1980)) ~/ 4;
    return (base + 0.242194 * (year - 1980) - leap).floor();
  }

  add(1, 1, '元日');
  add(1, year >= 2000 ? monday(1, 2) : 15, '成人の日');
  if (year >= 1967) add(2, 11, '建国記念の日');
  if (year >= 2020) add(2, 23, '天皇誕生日');
  add(3, equinox(true), '春分の日');
  add(
    4,
    29,
    year >= 2007
        ? '昭和の日'
        : year >= 1989
        ? 'みどりの日'
        : '天皇誕生日',
  );
  add(5, 3, '憲法記念日');
  if (year >= 2007) add(5, 4, 'みどりの日');
  add(5, 5, 'こどもの日');
  if (year == 2020) {
    add(7, 23, '海の日');
  } else if (year == 2021) {
    add(7, 22, '海の日');
  } else if (year >= 1996) {
    add(7, year >= 2003 ? monday(7, 3) : 20, '海の日');
  }
  if (year == 2020) {
    add(8, 10, '山の日');
  } else if (year == 2021) {
    add(8, 8, '山の日');
  } else if (year >= 2016) {
    add(8, 11, '山の日');
  }
  if (year >= 1966) add(9, year >= 2003 ? monday(9, 3) : 15, '敬老の日');
  add(9, equinox(false), '秋分の日');
  if (year == 2020) {
    add(7, 24, 'スポーツの日');
  } else if (year == 2021) {
    add(7, 23, 'スポーツの日');
  } else if (year >= 1966) {
    add(
      10,
      year >= 2000 ? monday(10, 2) : 10,
      year >= 2022
          ? 'スポーツの日'
          : year == 2019
          ? '体育の日（スポーツの日）'
          : '体育の日',
    );
  }
  add(11, 3, '文化の日');
  add(11, 23, '勤労感謝の日');
  if (year >= 1989 && year <= 2018) add(12, 23, '天皇誕生日');
  for (final special in const [
    (1959, 4, 10, '結婚の儀'),
    (1989, 2, 24, '大喪の礼'),
    (1990, 11, 12, '即位礼正殿の儀'),
    (1993, 6, 9, '結婚の儀'),
    (2019, 5, 1, '休日（祝日扱い）'),
    (2019, 10, 22, '休日（祝日扱い）'),
  ]) {
    if (special.$1 == year) add(special.$2, special.$3, special.$4);
  }
  final result = Map<DateTime, String>.of(national);
  final dates = national.keys.toList()..sort();
  for (final date in dates) {
    if (date.isBefore(DateTime.utc(1973, 4, 12)) ||
        date.weekday != DateTime.sunday) {
      continue;
    }
    var next = date.add(const Duration(days: 1));
    if (year >= 2007) {
      while (national.containsKey(next)) {
        next = next.add(const Duration(days: 1));
      }
    } else if (national.containsKey(next)) {
      continue;
    }
    result.putIfAbsent(next, () => '振替休日');
  }
  if (year >= 1986) {
    for (
      var day = DateTime.utc(year, 1, 2);
      day.isBefore(DateTime.utc(year, 12, 31));
      day = day.add(const Duration(days: 1))
    ) {
      if (result.containsKey(day) ||
          (year < 2007 && day.weekday == DateTime.sunday)) {
        continue;
      }
      if (national.containsKey(day.subtract(const Duration(days: 1))) &&
          national.containsKey(day.add(const Duration(days: 1)))) {
        result[day] = '休日';
      }
    }
  }
  return result;
});
