/// Name-class and token-stream helpers for ``RNCParser``. Kept in a separate
/// file so the parser proper stays within the type/file length budget.
extension RNCParser {
    // MARK: Name classes

    func parseNameClass(attribute: Bool) -> NameClass {
        var nameClass = parseSimpleNameClass(attribute: attribute)
        while peek() == .symbol("|") {
            advance()
            nameClass = .choice(nameClass, parseSimpleNameClass(attribute: attribute))
        }
        return nameClass
    }

    private func parseSimpleNameClass(attribute: Bool) -> NameClass {
        let base = parseNameClassPrimary(attribute: attribute)
        // `*` and `ns:*` may be narrowed by `- nameClass` subtraction.
        guard peek() == .symbol("-") else { return base }
        advance()
        return subtract(base, parseSimpleNameClass(attribute: attribute))
    }

    private func parseNameClassPrimary(attribute: Bool) -> NameClass {
        switch peek() {
        case .symbol("*"):
            advance()
            return .anyName
        case .symbol("("):
            advance()
            let nameClass = parseNameClass(attribute: attribute)
            expectSymbol(")")
            return nameClass
        // `prefix:*` lexes as the word `prefix:` (a `:` is a name character)
        // followed by a `*` symbol: a namespace wildcard.
        case let .word(word) where word.hasSuffix(":") && peek(1) == .symbol("*"):
            advance()
            advance()
            return .nsName(namespaces[String(word.dropLast())] ?? "")
        case let .word(word):
            advance()
            return qualifiedName(word, attribute: attribute)
        default:
            advance()
            return .anyName
        }
    }

    /// Applies name-class subtraction, which RELAX NG defines only for the open
    /// classes `anyName` (`*`) and `nsName` (`prefix:*`).
    private func subtract(_ base: NameClass, _ except: NameClass) -> NameClass {
        switch base {
        case .anyName: .anyNameExcept(except)
        case let .nsName(namespace): .nsNameExcept(namespace: namespace, except: except)
        default: base
        }
    }

    private func qualifiedName(_ word: String, attribute: Bool) -> NameClass {
        let parts = word.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            if parts[1] == "*" { return .nsName(namespaces[parts[0]] ?? "") }
            return .name(namespace: namespaces[parts[0]] ?? "", localName: parts[1])
        }
        return .name(namespace: attribute ? "" : defaultNamespace, localName: word)
    }

    // MARK: Token helpers

    func peek(_ offset: Int = 0) -> PureXML.Schema.RNCToken? {
        let index = position + offset
        return index < tokens.count ? tokens[index] : nil
    }

    @discardableResult
    func advance() -> PureXML.Schema.RNCToken? {
        defer { position += 1 }
        return peek()
    }

    func wordValue() -> String {
        if case let .word(word) = peek() { advance()
            return word
        }
        return ""
    }

    func expectAssignment() -> String {
        if case let .symbol(symbol) = peek(), symbol == "=" || symbol == "|=" || symbol == "&=" {
            advance()
            return symbol
        }
        return "="
    }

    func expectSymbol(_ symbol: String) {
        if peek() == .symbol(symbol) { advance() }
    }

    func expectString() -> String {
        if case let .string(value) = peek() { advance()
            return value
        }
        return ""
    }

    func strip(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }
}
