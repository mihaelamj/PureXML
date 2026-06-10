extension PureXML.Parsing.XMLDeclaration {
    /// A name/value pair from an XML declaration.
    struct PseudoAttribute: Equatable {
        let name: String
        let value: String
    }

    /// Scans the `name="value"` pseudo-attributes of an XML declaration's text.
    /// Each value must be quoted; anything malformed (a missing `=`, an unquoted
    /// value, trailing junk) makes the whole scan fail so the declaration is
    /// rejected rather than partly read.
    struct PseudoAttributeScanner {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) {
            chars = Array(text)
        }

        mutating func scan() -> [PseudoAttribute]? {
            var pairs: [PseudoAttribute] = []
            skipSpace()
            while index < chars.count {
                guard let name = scanName(), !name.isEmpty else { return nil }
                skipSpace()
                guard consume("=") else { return nil }
                skipSpace()
                guard let value = scanQuoted() else { return nil }
                pairs.append(PseudoAttribute(name: name, value: value))
                // Pseudo-attributes must be separated by whitespace.
                let before = index
                skipSpace()
                if index == before, index < chars.count { return nil }
            }
            return pairs
        }

        private mutating func scanName() -> String? {
            var name = ""
            while index < chars.count, isNameCharacter(chars[index]) {
                name.append(chars[index])
                index += 1
            }
            return name.isEmpty ? nil : name
        }

        private mutating func scanQuoted() -> String? {
            guard index < chars.count, chars[index] == "\"" || chars[index] == "'" else { return nil }
            let quote = chars[index]
            index += 1
            var value = ""
            while index < chars.count, chars[index] != quote {
                value.append(chars[index])
                index += 1
            }
            guard index < chars.count else { return nil }
            index += 1
            return value
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard index < chars.count, chars[index] == character else { return false }
            index += 1
            return true
        }

        private mutating func skipSpace() {
            while index < chars.count, chars[index] == " " || chars[index] == "\t" || chars[index] == "\n" || chars[index] == "\r" {
                index += 1
            }
        }

        private func isNameCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }
}
