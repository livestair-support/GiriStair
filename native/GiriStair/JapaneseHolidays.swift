import Foundation

// Holiday rules copied unchanged from LiveStair at 074206d2.

// MARK: - 日本の祝日（祝日法のルールから計算する）

// 祝日法（国民の祝日に関する法律）のルールで、その年の祝日を計算する（通信や取り込みは不要）。
// 1955年〜2025年は、内閣府の祝日CSVとすべて同じ日付になることを確かめている。
// 祝日の名前は内閣府の祝日CSVを基準に、振替休日は区別できる名前で表示する。
// 国民の休日はCSVに合わせて「休日」とする。
// 祝日法が変わったときや、一度きりの祝日ができたときは、ここを直す
enum JapaneseHolidayCalendar {
    private static let lock = NSLock()

    // 年ごとの祝日（キーは 1970年1月1日からの日数）。一度計算した年は覚えておく
    private static var holidaysByYear: [Int: [Int: String]] = [:]

    // 端末の時刻のタイムゾーンで、日付（年・月・日）を出す
    private static let gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
        return calendar
    }()

    // 一度きりの祝日（皇室の行事など）
    private static let specialHolidays: [(year: Int, month: Int, day: Int, name: String)] = [
        (1959, 4, 10, "結婚の儀"),
        (1989, 2, 24, "大喪の礼"),
        (1990, 11, 12, "即位礼正殿の儀"),
        (1993, 6, 9, "結婚の儀"),
        (2019, 5, 1, "休日（祝日扱い）"),
        (2019, 10, 22, "休日（祝日扱い）")
    ]

    static func holidayName(
        for date: Date
    ) -> String? {
        let components =
        gregorianCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return nil
        }

        return holidays(in: year)[
            daysFromCivil(
                year: year,
                month: month,
                day: day
            )
        ]
    }

    private static func holidays(
        in year: Int
    ) -> [Int: String] {
        lock.lock()

        if let cached = holidaysByYear[year] {
            lock.unlock()
            return cached
        }

        lock.unlock()

        let calculated =
        makeHolidays(
            year: year
        )

        lock.lock()
        holidaysByYear[year] = calculated
        lock.unlock()

        return calculated
    }

    // MARK: 祝日の計算

    private static func makeHolidays(
        year: Int
    ) -> [Int: String] {
        // 祝日法は1948年7月20日から
        guard year >= 1948 else {
            return [:]
        }

        var nationalHolidays: [Int: String] = [:]

        func add(
            _ month: Int,
            _ day: Int,
            _ name: String
        ) {
            nationalHolidays[
                daysFromCivil(
                    year: year,
                    month: month,
                    day: day
                )
            ] = name
        }

        add(1, 1, "元日")

        if year >= 2000 {
            add(1, nthMonday(year: year, month: 1, nth: 2), "成人の日")
        } else {
            add(1, 15, "成人の日")
        }

        if year >= 1967 {
            add(2, 11, "建国記念の日")
        }

        if year >= 2020 {
            add(2, 23, "天皇誕生日")
        }

        add(3, vernalEquinoxDay(year: year), "春分の日")

        if year >= 2007 {
            add(4, 29, "昭和の日")
        } else if year >= 1989 {
            add(4, 29, "みどりの日")
        } else {
            add(4, 29, "天皇誕生日")
        }

        add(5, 3, "憲法記念日")

        if year >= 2007 {
            add(5, 4, "みどりの日")
        }

        add(5, 5, "こどもの日")

        // 海の日（2020・2021年は東京オリンピック・パラリンピックで移動）
        if year == 2020 {
            add(7, 23, "海の日")
        } else if year == 2021 {
            add(7, 22, "海の日")
        } else if year >= 2003 {
            add(7, nthMonday(year: year, month: 7, nth: 3), "海の日")
        } else if year >= 1996 {
            add(7, 20, "海の日")
        }

        // 山の日（2020・2021年は移動）
        if year == 2020 {
            add(8, 10, "山の日")
        } else if year == 2021 {
            add(8, 8, "山の日")
        } else if year >= 2016 {
            add(8, 11, "山の日")
        }

        if year >= 2003 {
            add(9, nthMonday(year: year, month: 9, nth: 3), "敬老の日")
        } else if year >= 1966 {
            add(9, 15, "敬老の日")
        }

        add(9, autumnalEquinoxDay(year: year), "秋分の日")

        // スポーツの日（2019年までは体育の日。2020・2021年は移動）
        if year == 2020 {
            add(7, 24, "スポーツの日")
        } else if year == 2021 {
            add(7, 23, "スポーツの日")
        } else if year >= 2022 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "スポーツの日")
        } else if year == 2019 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "体育の日（スポーツの日）")
        } else if year >= 2000 {
            add(10, nthMonday(year: year, month: 10, nth: 2), "体育の日")
        } else if year >= 1966 {
            add(10, 10, "体育の日")
        }

        add(11, 3, "文化の日")
        add(11, 23, "勤労感謝の日")

        if year >= 1989,
           year <= 2018 {
            add(12, 23, "天皇誕生日")
        }

        for special in specialHolidays
        where special.year == year {
            add(special.month, special.day, special.name)
        }

        // 1948年は、祝日法ができた7月20日からの祝日だけ
        if year == 1948 {
            let lawStart =
            daysFromCivil(
                year: 1948,
                month: 7,
                day: 20
            )

            nationalHolidays =
            nationalHolidays.filter {
                $0.key >= lawStart
            }
        }

        var holidays =
        nationalHolidays

        // 振替休日（1973年4月12日から）：祝日が日曜日のとき。
        // 2006年までは翌日、2007年からは祝日でない一番近い日
        let substituteStart =
        daysFromCivil(
            year: 1973,
            month: 4,
            day: 12
        )

        for day in nationalHolidays.keys.sorted()
        where day >= substituteStart &&
        weekday(ofDays: day) == 0 {
            var nextDay =
            day + 1

            if year >= 2007 {
                while nationalHolidays[nextDay] != nil {
                    nextDay += 1
                }
            } else if nationalHolidays[nextDay] != nil {
                continue
            }

            if holidays[nextDay] == nil {
                holidays[nextDay] = "振替休日"
            }
        }

        // 国民の休日（1986年から）：前の日と次の日が祝日の日（2006年までは日曜日を除く）
        if year >= 1986 {
            let firstDay =
            daysFromCivil(
                year: year,
                month: 1,
                day: 1
            )

            let lastDay =
            daysFromCivil(
                year: year,
                month: 12,
                day: 31
            )

            for day in (firstDay + 1)..<lastDay
            where holidays[day] == nil {
                if year < 2007,
                   weekday(ofDays: day) == 0 {
                    continue
                }

                if nationalHolidays[day - 1] != nil,
                   nationalHolidays[day + 1] != nil {
                    holidays[day] = "休日"
                }
            }
        }

        return holidays
    }

    // 春分の日（3月の日にち。1980年より前は、割り算の端数を 0 の方へ切る式）
    private static func vernalEquinoxDay(
        year: Int
    ) -> Int {
        let base: Double
        let leapAdjustment: Int

        if year <= 1979 {
            base = 20.8357
            leapAdjustment = (year - 1983) / 4
        } else if year <= 2099 {
            base = 20.8431
            leapAdjustment = (year - 1980) / 4
        } else {
            base = 21.8510
            leapAdjustment = (year - 1980) / 4
        }

        return Int(
            floor(
                base +
                0.242194 * Double(year - 1980) -
                Double(leapAdjustment)
            )
        )
    }

    // 秋分の日（9月の日にち）
    private static func autumnalEquinoxDay(
        year: Int
    ) -> Int {
        let base: Double
        let leapAdjustment: Int

        if year <= 1979 {
            base = 23.2588
            leapAdjustment = (year - 1983) / 4
        } else if year <= 2099 {
            base = 23.2488
            leapAdjustment = (year - 1980) / 4
        } else {
            base = 24.2488
            leapAdjustment = (year - 1980) / 4
        }

        return Int(
            floor(
                base +
                0.242194 * Double(year - 1980) -
                Double(leapAdjustment)
            )
        )
    }

    // その月の n 回目の月曜日（日にち）
    private static func nthMonday(
        year: Int,
        month: Int,
        nth: Int
    ) -> Int {
        let firstWeekday =
        weekday(
            ofDays:
                daysFromCivil(
                    year: year,
                    month: month,
                    day: 1
                )
        )

        let offset =
        (1 - firstWeekday + 7) % 7

        return 1 + offset + (nth - 1) * 7
    }

    // MARK: 日付の計算（グレゴリオ暦）

    // 1970年1月1日からの日数
    private static func daysFromCivil(
        year: Int,
        month: Int,
        day: Int
    ) -> Int {
        let adjustedYear =
        month <= 2
        ? year - 1
        : year

        let era =
        (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400

        let yearOfEra =
        adjustedYear - era * 400

        let dayOfYear =
        (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1

        let dayOfEra =
        yearOfEra * 365 +
        yearOfEra / 4 -
        yearOfEra / 100 +
        dayOfYear

        return era * 146097 + dayOfEra - 719468
    }

    // 曜日（0 が日曜日）。1970年より前は日数がマイナスになるので、0〜6 にそろえる
    private static func weekday(
        ofDays days: Int
    ) -> Int {
        ((days + 4) % 7 + 7) % 7
    }
}

// 以前の「祝日CSVを取り込む」で保存していた祝日データ（今は使わないので消す）
private let legacyImportedJapaneseHolidaysKey =
"japaneseHolidaysDictionary"

func removeLegacyImportedJapaneseHolidays() {
    UserDefaults.standard.removeObject(
        forKey: legacyImportedJapaneseHolidaysKey
    )
}

