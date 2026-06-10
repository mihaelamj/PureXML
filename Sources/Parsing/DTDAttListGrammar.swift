extension PureXML.Parsing {
    /// Validates an `<!ATTLIST>` declaration body (everything after the element
    /// name) against the XML 1.0 grammar (productions 52-60): each definition is
    /// `S Name S AttType S DefaultDecl`, where the type is `CDATA`, a tokenized
    /// type, `NOTATION` with a name group, or an enumeration, and the default is
    /// `#REQUIRED`, `#IMPLIED`, or an optionally-`#FIXED` quoted value. The
    /// lenient `AttributeListParser` still drives behavior; this strict check
    /// runs at DTD scan time.
    enum DTDAttListGrammar {
        private static let tokenizedTypes: Set<String> = [
            "CDATA", "ID", "IDREF", "IDREFS", "ENTITY", "ENTITIES", "NMTOKEN", "NMTOKENS",
        ]

        static func isValid(_ body: String) -> Bool {
            var scanner = AttListScanner(body)
            while !scanner.isAtEnd {
                // Each definition starts with required whitespace (the body begins
                // right after the element name).
                guard scanner.requiredSpace() else { return false }
                if scanner.isAtEnd { return true } // trailing whitespace
                guard scanner.name() else { return false }
                guard scanner.requiredSpace() else { return false }
                guard attType(&scanner) else { return false }
                guard scanner.requiredSpace() else { return false }
                guard defaultDecl(&scanner) else { return false }
            }
            return true
        }

        private static func attType(_ scanner: inout AttListScanner) -> Bool {
            if scanner.peek() == "(" {
                return scanner.nameGroup(nmtokens: true)
            }
            guard let keyword = scanner.keyword() else { return false }
            if tokenizedTypes.contains(keyword) { return true }
            if keyword == "NOTATION" {
                guard scanner.requiredSpace() else { return false }
                return scanner.nameGroup(nmtokens: false)
            }
            return false
        }

        private static func defaultDecl(_ scanner: inout AttListScanner) -> Bool {
            if scanner.consumeLiteral("#REQUIRED") || scanner.consumeLiteral("#IMPLIED") {
                return true
            }
            if scanner.consumeLiteral("#FIXED") {
                guard scanner.requiredSpace() else { return false }
            }
            return scanner.quotedValue()
        }
    }
}

/// A tiny scanner over one attribute-list body.
private struct AttListScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    var isAtEnd: Bool {
        index >= characters.count
    }

    func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    /// Consumes at least one whitespace character.
    mutating func requiredSpace() -> Bool {
        let start = index
        while let character = peek(), character.isWhitespace {
            index += 1
        }
        return index > start
    }

    mutating func name() -> Bool {
        guard let first = peek(), first.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameStart) else {
            return false
        }
        index += 1
        while let next = peek(), next.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar) {
            index += 1
        }
        return true
    }

    /// An NMTOKEN: one or more name characters (the start may be any name char).
    private mutating func nmtoken() -> Bool {
        let start = index
        while let next = peek(), next.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar) {
            index += 1
        }
        return index > start
    }

    /// An uppercase keyword run (`CDATA`, `NOTATION`, ...).
    mutating func keyword() -> String? {
        let start = index
        while let next = peek(), next.isLetter {
            index += 1
        }
        guard index > start else { return nil }
        return String(characters[start ..< index])
    }

    /// `'(' S? token (S? '|' S? token)* S? ')'` with names or nmtokens.
    mutating func nameGroup(nmtokens: Bool) -> Bool {
        guard consume("(") else { return false }
        skipSpace()
        guard nmtokens ? nmtoken() : name() else { return false }
        skipSpace()
        while !consume(")") {
            guard consume("|") else { return false }
            skipSpace()
            guard nmtokens ? nmtoken() : name() else { return false }
            skipSpace()
        }
        return true
    }

    mutating func quotedValue() -> Bool {
        guard let quote = peek(), quote == "\"" || quote == "'" else { return false }
        index += 1
        while let next = peek(), next != quote {
            index += 1
        }
        return consume(quote)
    }

    mutating func consumeLiteral(_ literal: String) -> Bool {
        let count = literal.count
        guard index + count <= characters.count,
              String(characters[index ..< index + count]) == literal
        else { return false }
        index += count
        return true
    }

    private mutating func consume(_ character: Character) -> Bool {
        if peek() == character {
            index += 1
            return true
        }
        return false
    }

    private mutating func skipSpace() {
        while let character = peek(), character.isWhitespace {
            index += 1
        }
    }
}
