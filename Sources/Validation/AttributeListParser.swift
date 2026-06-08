extension PureXML.Validation {
    /// Parses a raw `<!ATTLIST>` body (the text after the element name) into a
    /// list of ``AttributeDeclaration``. Tolerant: unparseable trailing input is
    /// dropped rather than failing, so a damaged DTD never blocks the document.
    struct AttributeListParser {
        private let chars: [Character]
        private var index = 0

        private init(_ body: String) {
            chars = Array(body)
        }

        static func parse(_ body: String) -> [AttributeDeclaration] {
            var parser = AttributeListParser(body)
            return parser.parseAll()
        }

        private mutating func parseAll() -> [AttributeDeclaration] {
            var declarations: [AttributeDeclaration] = []
            while true {
                skipSpace()
                guard peek() != nil else { break }
                let name = parseName()
                guard !name.isEmpty else { break }
                skipSpace()
                let type = parseType()
                skipSpace()
                let defaultDecl = parseDefault()
                declarations.append(AttributeDeclaration(name: name, type: type, defaultDecl: defaultDecl))
            }
            return declarations
        }

        private mutating func parseType() -> AttributeType {
            if peek() == "(" {
                return .enumeration(parseEnumeration())
            }
            let token = parseName()
            if token == "NOTATION" {
                skipSpace()
                if peek() == "(" {
                    return .enumeration(parseEnumeration())
                }
            }
            return .cdata
        }

        private mutating func parseEnumeration() -> [String] {
            advance()
            var names: [String] = []
            while let character = peek(), character != ")" {
                if character == "|" {
                    advance()
                } else if isNameCharacter(character) {
                    names.append(parseName())
                } else {
                    advance()
                }
            }
            advance()
            return names
        }

        private mutating func parseDefault() -> AttributeDefault {
            if peek() == "#" {
                let token = parseHashToken()
                switch token {
                case "#REQUIRED": return .required
                case "#FIXED":
                    skipSpace()
                    return .fixed(parseLiteral())
                default: return .implied
                }
            }
            if let quote = peek(), quote == "\"" || quote == "'" {
                return .value(parseLiteral())
            }
            return .implied
        }

        private mutating func parseHashToken() -> String {
            var token = "#"
            advance()
            while let character = peek(), character.isLetter {
                token.append(character)
                advance()
            }
            return token
        }

        private mutating func parseLiteral() -> String {
            guard let quote = peek(), quote == "\"" || quote == "'" else { return "" }
            advance()
            var value = ""
            while let character = peek(), character != quote {
                value.append(character)
                advance()
            }
            if peek() == quote { advance() }
            return value
        }

        private mutating func parseName() -> String {
            var name = ""
            while let character = peek(), isNameCharacter(character) {
                name.append(character)
                advance()
            }
            return name
        }

        private func isNameCharacter(_ character: Character) -> Bool {
            switch character {
            case "(", ")", "|", "#", "\"", "'", " ", "\t", "\n", "\r": false
            default: true
            }
        }

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func advance() {
            if index < chars.count { index += 1 }
        }

        private mutating func skipSpace() {
            while let character = peek(), character == " " || character == "\t" || character == "\n" || character == "\r" {
                advance()
            }
        }
    }
}
