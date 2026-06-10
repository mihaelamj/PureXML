extension PureXML.Parsing {
    /// Validates a general entity's replacement text: per XML 1.0, character
    /// references in the entity value are expanded when the entity is declared,
    /// and the resulting replacement text must itself be well-formed `content`
    /// in isolation, balanced markup, complete references, no raw `<` outside a
    /// markup delimiter, legal names, and no reserved PI target. A replacement
    /// like `</foo><foo>` (tags spanning the entity boundary), `&` (an
    /// incomplete reference), or `<` followed by a non-name character is
    /// rejected at declaration.
    enum EntityReplacementGrammar {
        /// Expands character references the way entity declaration does, then
        /// checks the replacement parses as balanced content. Returns nil when
        /// valid, else a short reason.
        static func violation(inValue value: String) -> String? {
            guard let replacement = expandCharacterReferences(value) else {
                return "incomplete character reference"
            }
            return contentViolation(replacement)
        }

        /// One declaration-time pass over the entity value: `&#...;` becomes its
        /// character; everything else (including `&name;`) is kept verbatim.
        private static func expandCharacterReferences(_ value: String) -> String? {
            var result = ""
            let characters = Array(value)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if character == "&", index + 1 < characters.count, characters[index + 1] == "#" {
                    var probe = index + 2
                    var digits = ""
                    while probe < characters.count, characters[probe] != ";" {
                        digits.append(characters[probe])
                        probe += 1
                    }
                    guard probe < characters.count else { return nil }
                    let scalarValue: UInt32? = digits.hasPrefix("x")
                        ? UInt32(digits.dropFirst(), radix: 16)
                        : UInt32(digits, radix: 10)
                    guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else { return nil }
                    result.unicodeScalars.append(scalar)
                    index = probe + 1
                } else {
                    result.append(character)
                    index += 1
                }
            }
            return result
        }

        /// Reparses the replacement as content: balanced tags, complete
        /// references, no bare `<` or `&`.
        private static func contentViolation(_ replacement: String) -> String? {
            var scanner = ReplacementScanner(replacement)
            var depth = 0
            while let character = scanner.advance() {
                switch character {
                case "<":
                    if let reason = scanner.markup(depth: &depth) { return reason }
                case "&":
                    if !scanner.completeReference() { return "incomplete reference" }
                default:
                    break
                }
            }
            return depth == 0 ? nil : "unbalanced element tags"
        }
    }
}

/// A tiny scanner reparsing one replacement text.
private struct ReplacementScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    mutating func advance() -> Character? {
        guard index < characters.count else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    private func peek(_ ahead: Int = 0) -> Character? {
        index + ahead < characters.count ? characters[index + ahead] : nil
    }

    private mutating func consume(_ literal: String) -> Bool {
        let count = literal.count
        guard index + count <= characters.count,
              String(characters[index ..< index + count]) == literal
        else { return false }
        index += count
        return true
    }

    private mutating func skip(past terminator: String) -> Bool {
        while index < characters.count {
            if consume(terminator) { return true }
            index += 1
        }
        return false
    }

    /// Handles one markup construct after a consumed `<`.
    mutating func markup(depth: inout Int) -> String? {
        if consume("!--") {
            return skip(past: "-->") ? nil : "unterminated comment"
        }
        if consume("![CDATA[") {
            return skip(past: "]]>") ? nil : "unterminated CDATA section"
        }
        if consume("?") {
            guard let reason = processingInstruction() else { return "malformed processing instruction" }
            return reason.isEmpty ? nil : reason
        }
        let closing = consume("/")
        guard name() else { return "'<' is not followed by a name" }
        if closing {
            skipSpace()
            guard consume(">") else { return "malformed end tag" }
            depth -= 1
            return depth < 0 ? "an end tag closes an element opened outside the entity" : nil
        }
        if let reason = attributes() { return reason }
        if consume("/>") { return nil }
        guard consume(">") else { return "malformed start tag" }
        depth += 1
        return nil
    }

    /// Returns "" for a legal PI, a reason for an illegal one, nil if malformed.
    private mutating func processingInstruction() -> String? {
        let start = index
        guard name() else { return nil }
        let target = String(characters[start ..< index])
        guard skip(past: "?>") else { return nil }
        return target.lowercased() == "xml" ? "the processing-instruction target 'xml' is reserved" : ""
    }

    private mutating func attributes() -> String? {
        while true {
            skipSpace()
            guard let next = peek() else { return "unterminated start tag" }
            if next == ">" || next == "/" { return nil }
            guard name() else { return "malformed attribute name" }
            skipSpace()
            guard consume("=") else { return "attribute without a value" }
            skipSpace()
            if let reason = attributeValue() { return reason }
        }
    }

    /// One quoted attribute value: no raw `<`, complete references only.
    private mutating func attributeValue() -> String? {
        guard let quote = peek(), quote == "\"" || quote == "'" else { return "unquoted attribute value" }
        index += 1
        while let character = peek(), character != quote {
            if character == "<" { return "'<' in an attribute value" }
            if character == "&" {
                index += 1
                if !completeReference() { return "incomplete reference in an attribute value" }
                continue
            }
            index += 1
        }
        return consume(String(quote)) ? nil : "unterminated attribute value"
    }

    /// After a consumed `&`: a complete `name;` or `#digits;`.
    mutating func completeReference() -> Bool {
        var sawBody = false
        if peek() == "#" { index += 1 }
        while let character = peek(), character != ";" {
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar) else { return false }
            sawBody = true
            index += 1
        }
        guard sawBody, peek() == ";" else { return false }
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

    private mutating func skipSpace() {
        while let character = peek(), character.isWhitespace {
            index += 1
        }
    }
}
