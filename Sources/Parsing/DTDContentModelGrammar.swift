extension PureXML.Parsing {
    /// Validates an `<!ELEMENT>` content specification against the XML 1.0
    /// grammar (productions 46-51): `EMPTY`, `ANY`, `Mixed`, or `children`.
    /// The lenient `ContentModelParser` still drives validation behavior; this
    /// strict check runs at DTD scan time so a malformed model (unbalanced
    /// parentheses, `#PCDATA` misplacement, mixed connectors, a quantifier
    /// detached by whitespace, SGML leftovers) is rejected as not well-formed.
    enum DTDContentModelGrammar {
        static func isValid(_ model: String) -> Bool {
            let text = model.trimmingXMLWhitespace()
            if text == "EMPTY" || text == "ANY" { return true }
            var scanner = ModelScanner(text)
            guard scanner.peek() == "(" else { return false }
            // Mixed and children both start with '('; Mixed is identified by
            // '#PCDATA' as the first token inside.
            let isMixed = scanner.looksMixed()
            let parsed = isMixed ? scanner.mixed() : scanner.children()
            return parsed && scanner.isAtEnd
        }
    }
}

/// A tiny recursive-descent scanner over one content-model expression.
private struct ModelScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    var isAtEnd: Bool {
        index >= characters.count
    }

    func peek(_ ahead: Int = 0) -> Character? {
        index + ahead < characters.count ? characters[index + ahead] : nil
    }

    private mutating func advance() -> Character? {
        guard index < characters.count else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    private mutating func skipSpace() {
        while let character = peek(), character.isWhitespace {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        if peek() == character {
            index += 1
            return true
        }
        return false
    }

    /// Whether the expression opens as `( S? #PCDATA`.
    func looksMixed() -> Bool {
        var probe = self
        guard probe.consume("(") else { return false }
        probe.skipSpace()
        return probe.peek() == "#"
    }

    /// `Mixed ::= '(' S? '#PCDATA' (S? '|' S? Name)* S? ')*' | '(' S? '#PCDATA' S? ')'`
    mutating func mixed() -> Bool {
        guard consume("(") else { return false }
        skipSpace()
        guard consumeLiteral("#PCDATA") else { return false }
        var sawAlternative = false
        while true {
            skipSpace()
            if consume(")") { break }
            guard consume("|") else { return false }
            sawAlternative = true
            skipSpace()
            guard name() else { return false }
        }
        // With alternatives the trailing '*' is required; without, optional none.
        if sawAlternative {
            return consume("*")
        }
        return peek() != "*" || consume("*")
    }

    /// `children ::= (choice | seq) ('?' | '*' | '+')?` with
    /// `cp ::= (Name | choice | seq) ('?' | '*' | '+')?`. A group commits to one
    /// connector (`|` or `,`); a quantifier must follow its particle directly.
    mutating func children() -> Bool {
        guard group() else { return false }
        _ = quantifier()
        return true
    }

    private mutating func group() -> Bool {
        guard consume("(") else { return false }
        skipSpace()
        guard particle() else { return false }
        skipSpace()
        var connector: Character?
        while !consume(")") {
            guard let next = advance(), next == "|" || next == "," else { return false }
            if let connector, connector != next { return false }
            connector = next
            skipSpace()
            guard particle() else { return false }
            skipSpace()
        }
        return true
    }

    private mutating func particle() -> Bool {
        if peek() == "(" {
            guard group() else { return false }
        } else {
            guard name() else { return false }
        }
        _ = quantifier()
        return true
    }

    /// A quantifier binds directly to its particle: no whitespace before it,
    /// and at most one.
    private mutating func quantifier() -> Bool {
        guard let next = peek(), next == "?" || next == "*" || next == "+" else { return false }
        index += 1
        return true
    }

    private mutating func name() -> Bool {
        guard let first = peek(), first.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameStart) else {
            return false
        }
        index += 1
        while let next = peek(), next.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar) {
            index += 1
        }
        return true
    }

    private mutating func consumeLiteral(_ literal: String) -> Bool {
        let count = literal.count
        guard index + count <= characters.count,
              String(characters[index ..< index + count]) == literal
        else { return false }
        index += count
        return true
    }
}
