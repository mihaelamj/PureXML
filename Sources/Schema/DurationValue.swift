extension PureXML.Schema {
    /// The outcome of comparing two durations, which form a partial order.
    enum DurationOrder { case lessThan, equal, greaterThan, incomparable }

    /// An `xs:duration` as its two independent signed components, months and
    /// seconds, with the XSD 1.0 order relation. Because a month is 28 to 31
    /// days, the order is partial: P and Q compare by adding each to the four
    /// reference dateTimes the spec fixes, and durations whose sign disagrees
    /// across those references are incomparable (for example `P1M` and `P30D`).
    /// See XSD 1.0 Datatypes 3.2.6.2. Used by the ordering facets on duration,
    /// which the generic total-order path cannot represent.
    struct DurationValue {
        let months: Int
        let seconds: Double

        /// The four reference points (year, month); each is the first of its
        /// month at T00:00:00Z, so the day is always 1 and need not be carried.
        private static let references: [(year: Int, month: Int)] = [
            (1696, 9), (1697, 2), (1903, 3), (1903, 7),
        ]

        func compare(to other: DurationValue) -> DurationOrder {
            var sawLess = false
            var sawGreater = false
            var sawEqual = false
            for reference in Self.references {
                let here = Self.instant(reference, addingMonths: months, seconds: seconds)
                let there = Self.instant(reference, addingMonths: other.months, seconds: other.seconds)
                if here < there {
                    sawLess = true
                } else if here > there {
                    sawGreater = true
                } else {
                    sawEqual = true
                }
            }
            // P < Q only when s+P < s+Q at every reference; > likewise; equal
            // when all four coincide (which holds iff the components are equal).
            if sawLess, !sawGreater, !sawEqual { return .lessThan }
            if sawGreater, !sawLess, !sawEqual { return .greaterThan }
            if sawEqual, !sawLess, !sawGreater { return .equal }
            return .incomparable
        }

        /// The instant, in seconds, of `reference` + (months, seconds): add the
        /// months with calendar rollover, then add the seconds. The reference
        /// day is always 1, which is valid in every month, so no day clamping is
        /// needed (a duration's day component lives in `seconds`, not here).
        private static func instant(
            _ reference: (year: Int, month: Int),
            addingMonths addMonths: Int,
            seconds: Double,
        ) -> Double {
            let total = (reference.month - 1) + addMonths
            let yearsCarried = Int((Double(total) / 12.0).rounded(.down))
            let newYear = reference.year + yearsCarried
            let newMonth = total - yearsCarried * 12 + 1
            let days = DateTimeValue.daysFromCivil(year: newYear, month: newMonth, day: 1)
            return Double(days) * 86400 + seconds
        }

        /// Parses the lexical form `-?P(nY)?(nM)?(nD)?(T(nH)?(nM)?(nS)?)?`. The
        /// lexical recognizer has already accepted the value, so this trusts the
        /// shape and only reads out the components.
        init?(_ string: String) {
            var characters = Substring(string)
            var sign = 1.0
            if characters.first == "-" {
                sign = -1
                characters = characters.dropFirst()
            }
            guard characters.first == "P" else { return nil }
            characters = characters.dropFirst()

            var inTime = false
            var years = 0
            var monthsPart = 0
            var days = 0
            var secondsPart = 0.0
            var sawComponent = false
            var number = ""

            func consume(_ designator: Character) -> Bool {
                guard !number.isEmpty, let magnitude = Double(number) else { return false }
                switch (inTime, designator) {
                case (false, "Y"): years = Int(magnitude)
                case (false, "M"): monthsPart = Int(magnitude)
                case (false, "D"): days = Int(magnitude)
                case (true, "H"): secondsPart += magnitude * 3600
                case (true, "M"): secondsPart += magnitude * 60
                case (true, "S"): secondsPart += magnitude
                default: return false
                }
                number = ""
                sawComponent = true
                return true
            }

            for character in characters {
                if character == "T" {
                    inTime = true
                } else if character.isNumber || character == "." {
                    number.append(character)
                } else if !consume(character) {
                    return nil
                }
            }
            guard sawComponent, number.isEmpty else { return nil }
            months = Int(sign) * (years * 12 + monthsPart)
            seconds = sign * (Double(days) * 86400 + secondsPart)
        }
    }
}
