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
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\r" where escapeCarriageReturn: result += "&#xD;"
                default: result += plain(character, asciiOnly: asciiOnly)
                }
            }
            return result
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
            for character in value {
                if character == quote {
                    result += quote == "'" ? "&apos;" : "&quot;"
                    continue
                }
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\t": result += "&#9;"
                case "\n": result += "&#10;"
                case "\r": result += "&#13;"
                default: result += plain(character, asciiOnly: asciiOnly)
                }
            }
            return result
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
