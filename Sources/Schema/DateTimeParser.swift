extension PureXML.Schema {
    /// Parses an XSD date/time lexical form for a given ``DateKind``, validating
    /// field ranges (including leap years and the `24:00:00` midnight form) and
    /// the timezone. Returns nil when the form is invalid.
    struct DateTimeParser {
        private let chars: [Character]
        private var index = 0

        private init(_ lexical: String) {
            chars = Array(lexical)
        }

        static func parse(_ lexical: String, kind: DateKind) -> DateTimeValue? {
            var parser = DateTimeParser(lexical)
            guard var value = parser.parseFields(kind) else { return nil }
            guard parser.parseTimezone(into: &value) else { return nil }
            return parser.isAtEnd ? value : nil
        }

        private mutating func parseFields(_ kind: DateKind) -> DateTimeValue? {
            switch kind {
            case .dateTime: parseDateTime()
            case .date: parseDate()
            case .time: parseTimeOnly()
            case .gYearMonth: parseYearMonth()
            case .gYear: parseYearOnly()
            case .gMonthDay: parseMonthDay()
            case .gDay: parseDayOnly()
            case .gMonth: parseMonthOnly()
            }
        }

        // MARK: Composite forms

        private mutating func parseDateTime() -> DateTimeValue? {
            guard var value = parseDate(), consume("T") else { return nil }
            return parseTime(into: &value) ? value : nil
        }

        private mutating func parseDate() -> DateTimeValue? {
            guard var value = parseYearMonth(), consume("-"), let day = readFixed(2) else { return nil }
            value.day = day
            return dayInRange(value) ? value : nil
        }

        private mutating func parseYearMonth() -> DateTimeValue? {
            guard var value = parseYearOnly(), consume("-"), let month = readFixed(2), (1 ... 12).contains(month) else {
                return nil
            }
            value.month = month
            return value
        }

        private mutating func parseYearOnly() -> DateTimeValue? {
            var value = DateTimeValue()
            let negative = consume("-")
            // XSD 1.0 has no year zero: the lexical year 0000 (and -0000) is not a
            // valid value for dateTime, date, gYearMonth, or gYear. `digits` is the
            // magnitude, so rejecting 0 covers both signs.
            guard let digits = readDigits(minimum: 4), digits != 0 else { return nil }
            value.year = (negative ? -1 : 1) * digits
            return value
        }

        private mutating func parseTimeOnly() -> DateTimeValue? {
            var value = DateTimeValue()
            return parseTime(into: &value) ? value : nil
        }

        // MARK: g* forms

        private mutating func parseMonthDay() -> DateTimeValue? {
            guard consume("--"), let month = readFixed(2), (1 ... 12).contains(month), consume("-"),
                  let day = readFixed(2) else { return nil }
            let value = DateTimeValue(year: 2000, month: month, day: day)
            return dayInRange(value) ? value : nil
        }

        private mutating func parseMonthOnly() -> DateTimeValue? {
            guard consume("--"), let month = readFixed(2), (1 ... 12).contains(month) else { return nil }
            // XSD 1.0 gMonth is `--MM--`; the later erratum/1.1 form `--MM` is also
            // accepted, so the trailing `--` is optional. A timezone may follow either.
            _ = consume("--")
            return DateTimeValue(month: month)
        }

        private mutating func parseDayOnly() -> DateTimeValue? {
            guard consume("---"), let day = readFixed(2), (1 ... 31).contains(day) else { return nil }
            return DateTimeValue(day: day)
        }

        // MARK: Time and timezone

        private mutating func parseTime(into value: inout DateTimeValue) -> Bool {
            guard let hour = readFixed(2), consume(":"), let minute = readFixed(2), consume(":"),
                  let second = readFixed(2) else { return false }
            guard (0 ... 24).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second) else { return false }
            if hour == 24, minute != 0 || second != 0 { return false }
            value.hour = hour
            value.minute = minute
            value.second = second
            if consume(".") {
                guard let fraction = readFraction() else { return false }
                value.fraction = fraction
            }
            return true
        }

        private mutating func parseTimezone(into value: inout DateTimeValue) -> Bool {
            if consume("Z") { value.offsetMinutes = 0
                return true
            }
            guard peek() == "+" || peek() == "-" else { return true }
            let negative = consume("-")
            if !negative { advance() }
            guard let hour = readFixed(2), consume(":"), let minute = readFixed(2) else { return false }
            guard (0 ... 14).contains(hour), (0 ... 59).contains(minute), hour * 60 + minute <= 14 * 60 else {
                return false
            }
            value.offsetMinutes = (negative ? -1 : 1) * (hour * 60 + minute)
            return true
        }

        private func dayInRange(_ value: DateTimeValue) -> Bool {
            (1 ... DateTimeValue.daysInMonth(year: value.year, month: value.month)).contains(value.day)
        }

        // MARK: Cursor

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func advance() {
            if index < chars.count { index += 1 }
        }

        private mutating func consume(_ literal: String) -> Bool {
            let target = Array(literal)
            guard index + target.count <= chars.count, Array(chars[index ..< index + target.count]) == target else {
                return false
            }
            index += target.count
            return true
        }

        /// Reads exactly `count` digits as an integer, or nil.
        private mutating func readFixed(_ count: Int) -> Int? {
            guard index + count <= chars.count else { return nil }
            let slice = chars[index ..< index + count]
            guard slice.allSatisfy(\.isNumber) else { return nil }
            index += count
            return Int(String(slice))
        }

        /// Reads at least `minimum` digits as an integer.
        private mutating func readDigits(minimum: Int) -> Int? {
            let start = index
            while let character = peek(), character.isNumber {
                advance()
            }
            guard index - start >= minimum else { return nil }
            return Int(String(chars[start ..< index]))
        }

        /// Reads the fractional seconds after the decimal point.
        private mutating func readFraction() -> Double? {
            let start = index
            while let character = peek(), character.isNumber {
                advance()
            }
            guard index > start else { return nil }
            return Double("0." + String(chars[start ..< index]))
        }
    }
}
