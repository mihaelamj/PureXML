extension PureXML.Schema {
    /// Lexical recognizers for the XSD primitive value spaces that are not date or
    /// decimal. Each takes an already whiteSpace-processed string.
    enum Lexical {
        static func isBoolean(_ value: String) -> Bool {
            value == "true" || value == "false" || value == "0" || value == "1"
        }

        /// `float`/`double`: an optional-sign mantissa with an optional exponent,
        /// or the special values `INF`, `-INF`, `NaN`.
        static func isFloating(_ value: String) -> Bool {
            if value == "INF" || value == "-INF" || value == "NaN" { return true }
            var characters = Substring(value)
            if characters.first == "+" || characters.first == "-" { characters = characters.dropFirst() }
            let exponentSplit = characters.split(separator: "e", omittingEmptySubsequences: false)
            let altSplit = characters.split(separator: "E", omittingEmptySubsequences: false)
            let parts = exponentSplit.count == 2 ? exponentSplit : altSplit
            guard parts.count <= 2 else { return false }
            guard isDecimalMantissa(parts[0]) else { return false }
            return parts.count == 1 || isSignedInteger(parts[1])
        }

        private static func isDecimalMantissa(_ value: Substring) -> Bool {
            let segments = value.split(separator: ".", omittingEmptySubsequences: false)
            guard segments.count <= 2 else { return false }
            let whole = segments[0]
            let fraction = segments.count == 2 ? segments[1] : Substring("")
            guard whole.allSatisfy(\.isNumber), fraction.allSatisfy(\.isNumber) else { return false }
            return !whole.isEmpty || !fraction.isEmpty
        }

        private static func isSignedInteger(_ value: Substring) -> Bool {
            var digits = value
            if digits.first == "+" || digits.first == "-" { digits = digits.dropFirst() }
            return !digits.isEmpty && digits.allSatisfy(\.isNumber)
        }

        /// `duration`: `-?P(nY)?(nM)?(nD)?(T(nH)?(nM)?(nS, with fraction)?)?` with at
        /// least one component and no empty `T`.
        static func isDuration(_ value: String) -> Bool {
            var rest = Substring(value)
            if rest.first == "-" { rest = rest.dropFirst() }
            guard rest.first == "P" else { return false }
            rest = rest.dropFirst()
            let timeSplit = rest.split(separator: "T", omittingEmptySubsequences: false)
            guard timeSplit.count <= 2 else { return false }
            let datePart = timeSplit[0]
            let timePart = timeSplit.count == 2 ? timeSplit[1] : nil
            let dateOK = matchDuration(datePart, designators: "YMD", allowFraction: false)
            guard let dateCount = dateOK else { return false }
            guard let timePart else { return dateCount > 0 }
            guard let timeCount = matchDuration(timePart, designators: "HMS", allowFraction: true), timeCount > 0 else {
                return false
            }
            return true
        }

        /// Matches a run of `<number><designator>` groups in the given designator
        /// order, returning the group count or nil on a malformed run.
        private static func matchDuration(_ value: Substring, designators: String, allowFraction: Bool) -> Int? {
            var rest = value
            var remaining = Array(designators)
            var count = 0
            while !rest.isEmpty {
                let digits = rest.prefix { $0.isNumber || (allowFraction && $0 == ".") }
                guard !digits.isEmpty, isUnsignedNumber(digits, allowFraction: allowFraction) else { return nil }
                rest = rest.dropFirst(digits.count)
                guard let designator = rest.first, let position = remaining.firstIndex(of: designator) else { return nil }
                remaining.removeFirst(position + 1)
                rest = rest.dropFirst()
                count += 1
            }
            return count
        }

        private static func isUnsignedNumber(_ value: Substring, allowFraction: Bool) -> Bool {
            guard allowFraction else { return value.allSatisfy(\.isNumber) }
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, parts[0].allSatisfy(\.isNumber) else { return false }
            return parts.count == 1 || parts[1].allSatisfy(\.isNumber)
        }

        static func isHexBinary(_ value: String) -> Bool {
            value.count.isMultiple(of: 2) && value.allSatisfy(\.isHexDigit)
        }

        static func isBase64Binary(_ value: String) -> Bool {
            guard value.count.isMultiple(of: 4) else { return value.isEmpty }
            let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
            let body = value.prefix { alphabet.contains($0) }
            let padding = value.dropFirst(body.count)
            return padding.allSatisfy { $0 == "=" } && padding.count <= 2
        }

        static func isLanguage(_ value: String) -> Bool {
            let parts = value.split(separator: "-", omittingEmptySubsequences: false)
            guard let first = parts.first, (1 ... 8).contains(first.count), first.allSatisfy(\.isLetter) else {
                return false
            }
            return parts.dropFirst().allSatisfy { (1 ... 8).contains($0.count) && $0.allSatisfy(\.isLetterOrDigit) }
        }

        static func isNCName(_ value: String) -> Bool {
            !value.contains(":") && isName(value)
        }

        static func isQName(_ value: String) -> Bool {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            switch parts.count {
            case 1: return isName(value)
            case 2: return isNCName(String(parts[0])) && isNCName(String(parts[1]))
            default: return false
            }
        }

        static func isName(_ value: String) -> Bool {
            PureXML.Parsing.XMLCharacter.isValidName(value)
        }

        static func isNMToken(_ value: String) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar)
        }
    }
}

private extension Character {
    var isLetterOrDigit: Bool {
        isLetter || isNumber
    }
}
