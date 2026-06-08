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
                let defaultDecl = parseDefault(type: type)
                declarations.append(AttributeDeclaration(name: name, type: type, defaultDecl: defaultDecl))
            }
            return declarations
        }

        private mutating func parseType() -> AttributeType {
            if peek() == "(" {
                return .enumeration(parseEnumeration())
            }
            let token = parseName()
            switch token {
            case "ID": return .id
            case "IDREF": return .idReference
            case "IDREFS": return .idReferences
            case "NMTOKEN": return .nmToken
            case "NMTOKENS": return .nmTokens
            case "ENTITY": return .entity
            case "ENTITIES": return .entities
            case "NOTATION":
                skipSpace()
                return peek() == "(" ? .notation(parseEnumeration()) : .cdata
            default:
                return .cdata
            }
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

        private mutating func parseDefault(type: AttributeType) -> AttributeDefault {
            if peek() == "#" {
                let token = parseHashToken()
                switch token {
                case "#REQUIRED": return .required
                case "#FIXED":
                    skipSpace()
                    return .fixed(Self.normalize(parseLiteral(), type: type))
                default: return .implied
                }
            }
            if let quote = peek(), quote == "\"" || quote == "'" {
                return .value(Self.normalize(parseLiteral(), type: type))
            }
            return .implied
        }

        /// Normalizes a DTD default attribute value per XML 1.0 attribute-value
        /// normalization: character and predefined-entity references are expanded,
        /// each literal whitespace character becomes a space, and for every type
        /// other than CDATA leading and trailing spaces are stripped and internal
        /// runs collapsed. General (non-predefined) entity references are left as
        /// written, since the referenced entities are not resolved here.
        static func normalize(_ raw: String, type: AttributeType) -> String {
            let expanded = expandReferences(raw)
            let spaced = String(expanded.map { ($0 == "\t" || $0 == "\n" || $0 == "\r") ? " " : $0 })
            guard type != .cdata else { return spaced }
            return spaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }

        private static func expandReferences(_ raw: String) -> String {
            var result = ""
            let chars = Array(raw)
            var index = 0
            while index < chars.count {
                guard chars[index] == "&", let semicolon = chars[(index + 1)...].firstIndex(of: ";") else {
                    result.append(chars[index])
                    index += 1
                    continue
                }
                let reference = String(chars[(index + 1) ..< semicolon])
                if let resolved = resolveReference(reference) {
                    result.append(resolved)
                } else {
                    result += "&\(reference);"
                }
                index = semicolon + 1
            }
            return result
        }

        private static func resolveReference(_ reference: String) -> Character? {
            switch reference {
            case "lt": return "<"
            case "gt": return ">"
            case "amp": return "&"
            case "apos": return "'"
            case "quot": return "\""
            default: break
            }
            guard reference.hasPrefix("#") else { return nil }
            let digits = reference.dropFirst()
            let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
            let value = isHex ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
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
