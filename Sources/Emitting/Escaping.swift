extension PureXML.Emitting {
    /// The shared XML output escaping rules, used by both the tree serializer and
    /// the incremental writer so their output is identical. Element content
    /// escapes the markup characters; attribute values additionally escape the
    /// quote and the whitespace characters as numeric references (matching
    /// libxml2), so attributes survive attribute-value normalization.
    enum Escaping {
        static func text(_ value: String, asciiOnly: Bool = false, escapeCarriageReturn: Bool = false) -> String {
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

        /// Makes `value` safe inside a comment: a comment may not contain `--`
        /// or end with `-`, so a space is inserted after each offending hyphen
        /// (the XSLT 1.0 16 recovery, so `after-` becomes `after- `).
        static func comment(_ value: String) -> String {
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
