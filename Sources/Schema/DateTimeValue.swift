extension PureXML.Schema {
    /// The eight XSD date/time datatypes, distinguished by which fields their
    /// lexical form carries.
    enum DateKind: Sendable {
        case dateTime
        case date
        case time
        case gYearMonth
        case gYear
        case gMonthDay
        case gDay
        case gMonth
    }

    /// A parsed and range-validated XSD date/time value, with a UTC-normalized key
    /// for ordering facet bounds. Values without a timezone are ordered as if in
    /// UTC, which gives the total order facet checking needs.
    struct DateTimeValue: Equatable, Comparable, Sendable {
        var year = 1
        var month = 1
        var day = 1
        var hour = 0
        var minute = 0
        var second = 0
        var fraction = 0.0
        var offsetMinutes = 0

        static func < (lhs: DateTimeValue, rhs: DateTimeValue) -> Bool {
            lhs.key < rhs.key
        }

        /// Seconds from a fixed epoch in UTC, the ordering key.
        private var key: Double {
            let days = Self.daysFromCivil(year: year, month: month, day: day)
            let seconds = Double(days * 86400 + hour * 3600 + minute * 60 + second)
            return seconds + fraction - Double(offsetMinutes * 60)
        }

        /// The civil-date-to-day-count algorithm (proleptic Gregorian), valid for
        /// any year. Day 0 is 1970-01-01.
        static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
            let shifted = month <= 2 ? year - 1 : year
            let era = (shifted >= 0 ? shifted : shifted - 399) / 400
            let yearOfEra = shifted - era * 400
            let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097 + dayOfEra - 719_468
        }

        static func isLeapYear(_ year: Int) -> Bool {
            (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        }

        static func daysInMonth(year: Int, month: Int) -> Int {
            switch month {
            case 1, 3, 5, 7, 8, 10, 12: 31
            case 4, 6, 9, 11: 30
            default: isLeapYear(year) ? 29 : 28
            }
        }
    }
}
