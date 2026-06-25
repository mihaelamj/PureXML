extension PureXML.Emitting {
    /// The shared XML output escaping rules, used by both the tree serializer and
    /// the incremental writer so their output is identical. Element content
    /// escapes the markup characters; attribute values additionally escape the
    /// quote and the whitespace characters as numeric references (matching
    /// libxml2), so attributes survive attribute-value normalization.
    enum Escaping {
        static func text(_ value: String, asciiOnly: Bool = false, escapeCarriageReturn: Bool = false) -> String {
            // Fast path: most content has no character that needs escaping, so it
            // is returned unchanged rather than rebuilt character by character.
            if !textNeedsEscaping(value, asciiOnly: asciiOnly, escapeCarriageReturn: escapeCarriageReturn) {
                return value
            }
            var result = ""
            var runStart = value.startIndex
            // Find each character that needs escaping by scanning bytes (every
            // trigger is an ASCII marker, or in ASCII-only mode a non-ASCII lead
            // byte, both of which fall on a grapheme boundary), copy the verbatim
            // run before it in one append, and rewrite only that character.
            while let marker = value.utf8[runStart...].firstIndex(where: {
                textEscapableByte($0, asciiOnly: asciiOnly, escapeCarriageReturn: escapeCarriageReturn)
            }) {
                if runStart < marker { result += value[runStart ..< marker] }
                let character = value[marker]
                result += textEscape(character, asciiOnly: asciiOnly, escapeCarriageReturn: escapeCarriageReturn) ?? String(character)
                runStart = value.index(after: marker)
            }
            if runStart < value.endIndex { result += value[runStart...] }
            return result
        }

        /// Whether a byte can begin a character ``text`` must escape: an ASCII
        /// markup byte, a carriage return when asked, or any non-ASCII lead byte
        /// in ASCII-only mode (its character is reference-escaped whole).
        private static func textEscapableByte(_ byte: UInt8, asciiOnly: Bool, escapeCarriageReturn: Bool) -> Bool {
            switch byte {
            case 0x26, 0x3C, 0x3E: true
            case 0x0D where escapeCarriageReturn: true
            case 0x80... where asciiOnly: true
            default: false
            }
        }

        /// The escaped form of one content character, or nil when it is verbatim.
        private static func textEscape(_ character: Character, asciiOnly: Bool, escapeCarriageReturn: Bool) -> String? {
            switch character {
            case "&": "&amp;"
            case "<": "&lt;"
            case ">": "&gt;"
            case "\r" where escapeCarriageReturn: "&#xD;"
            default: asciiOnly ? plainIfNonASCII(character) : nil
            }
        }

        /// Whether ``text`` would change `value`: it escapes `&`, `<`, `>` always,
        /// a carriage return when asked, and (in ASCII-only mode) any non-ASCII
        /// byte. Scanned at the byte level, since every trigger is ASCII or, for
        /// ASCII-only mode, a non-ASCII lead byte.
        private static func textNeedsEscaping(_ value: String, asciiOnly: Bool, escapeCarriageReturn: Bool) -> Bool {
            for byte in value.utf8 {
                switch byte {
                case 0x26, 0x3C, 0x3E: return true
                case 0x0D where escapeCarriageReturn: return true
                case 0x80... where asciiOnly: return true
                default: continue
                }
            }
            return false
        }

        /// In ASCII-only mode, the numeric-reference escaping of a character that
        /// carries a non-ASCII scalar, or nil when the character is pure ASCII and
        /// so is copied verbatim with its run.
        private static func plainIfNonASCII(_ character: Character) -> String? {
            guard character.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return nil }
            return plain(character, asciiOnly: true)
        }

        /// A character verbatim, or, in ASCII-only mode, each of its non-ASCII
        /// scalars as a numeric character reference so the output is pure ASCII.
        private static func plain(_ character: Character, asciiOnly: Bool) -> String {
            guard asciiOnly else { return String(character) }
            var result = ""
            for scalar in character.unicodeScalars {
                result += scalar.value > 0x7F ? "&#x\(String(scalar.value, radix: 16, uppercase: true));" : String(scalar)
            }
            return result
        }

        static func attribute(_ value: String, quote: Character = "\"", asciiOnly: Bool = false) -> String {
            // Fast path: a value with no character to escape is returned unchanged.
            let quoteByte: UInt8 = quote == "'" ? 0x27 : 0x22
            if !attributeNeedsEscaping(value, quoteByte: quoteByte, asciiOnly: asciiOnly) {
                return value
            }
            var result = ""
            var runStart = value.startIndex
            while let marker = value.utf8[runStart...].firstIndex(where: {
                attributeEscapableByte($0, quoteByte: quoteByte, asciiOnly: asciiOnly)
            }) {
                if runStart < marker { result += value[runStart ..< marker] }
                let character = value[marker]
                result += attributeEscape(character, quote: quote, asciiOnly: asciiOnly) ?? String(character)
                runStart = value.index(after: marker)
            }
            if runStart < value.endIndex { result += value[runStart...] }
            return result
        }

        /// Whether a byte can begin a character ``attribute`` must escape: the
        /// quote, an ASCII markup or whitespace byte, or a non-ASCII lead byte in
        /// ASCII-only mode.
        private static func attributeEscapableByte(_ byte: UInt8, quoteByte: UInt8, asciiOnly: Bool) -> Bool {
            switch byte {
            case quoteByte, 0x26, 0x3C, 0x3E, 0x09, 0x0A, 0x0D: true
            case 0x80... where asciiOnly: true
            default: false
            }
        }

        /// The escaped form of one attribute-value character, or nil when it is
        /// copied verbatim. Split out so ``attribute`` stays a simple run loop.
        private static func attributeEscape(_ character: Character, quote: Character, asciiOnly: Bool) -> String? {
            if character == quote {
                return quote == "'" ? "&apos;" : "&quot;"
            }
            switch character {
            case "&": return "&amp;"
            case "<": return "&lt;"
            case ">": return "&gt;"
            case "\t": return "&#9;"
            case "\n": return "&#10;"
            case "\r": return "&#13;"
            default: return asciiOnly ? plainIfNonASCII(character) : nil
            }
        }

        /// Whether ``attribute`` would change `value`: it escapes the quote, the
        /// markup characters, the whitespace characters, and (in ASCII-only mode)
        /// any non-ASCII byte. Every trigger is ASCII bar the non-ASCII lead.
        private static func attributeNeedsEscaping(_ value: String, quoteByte: UInt8, asciiOnly: Bool) -> Bool {
            for byte in value.utf8 {
                switch byte {
                case quoteByte, 0x26, 0x3C, 0x3E, 0x09, 0x0A, 0x0D: return true
                case 0x80... where asciiOnly: return true
                default: continue
                }
            }
            return false
        }

        /// Makes `value` safe inside a comment: a comment may not contain `--`
        /// or end with `-`, so a space is inserted after each offending hyphen
        /// (the XSLT 1.0 16 recovery, so `after-` becomes `after- `).
        static func comment(_ value: String) -> String {
            // Fast path: a comment with no hyphen has no `--` and no trailing `-`,
            // so it is returned unchanged rather than rebuilt character by character.
            if !value.utf8.contains(0x2D) { return value }
            var result = ""
            var previousHyphen = false
            for character in value {
                if character == "-", previousHyphen { result.append(" ") }
                result.append(character)
                previousHyphen = character == "-"
            }
            if previousHyphen { result.append(" ") }
            return result
        }

        /// Makes `data` safe inside a processing instruction: PI data may not
        /// contain `?>`, so a space is inserted between an offending `?` and `>`
        /// (the XSLT 1.0 7.3 recovery, so `a?>b` becomes `a? >b`).
        static func processingInstruction(_ data: String) -> String {
            // Fast path: data with no '?' cannot contain `?>`, so it is returned
            // unchanged rather than rebuilt character by character.
            if !data.utf8.contains(0x3F) { return data }
            var result = ""
            var previousQuestion = false
            for character in data {
                if character == ">", previousQuestion { result.append(" ") }
                result.append(character)
                previousQuestion = character == "?"
            }
            return result
        }
    }
}
