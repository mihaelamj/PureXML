private typealias RNCToken = PureXML.Schema.RNCToken
private typealias RNCLexer = PureXML.Schema.RNCLexer

/// A recursive-descent parser from the token stream to the pattern algebra.
/// File-scope and private.
private final class RNCParser {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass

    private let tokens: [RNCToken]
    private var position = 0
    private let loader: (String) -> String?
    private(set) var defines: [String: Pattern] = [:]
    private var startPattern: Pattern?
    private var defaultNamespace = ""
    private var namespaces: [String: String] = [:]
    private var visited: Set<String>

    init(_ tokens: [RNCToken], loader: @escaping (String) -> String?, visited: Set<String> = []) {
        self.tokens = tokens
        self.loader = loader
        self.visited = visited
    }

    func parse() -> (start: Pattern, defines: [String: Pattern]) {
        skipDeclarations()
        if looksLikeGrammar() {
            parseGrammarBody()
            return (startPattern ?? .notAllowed, defines)
        }
        return (parsePattern(), defines)
    }

    // MARK: Declarations

    private func skipDeclarations() {
        while case let .word(keyword) = peek() {
            switch keyword {
            case "namespace": parseNamespace(isDefault: false)
            case "default": parseDefault()
            case "datatypes": parseDatatypes()
            default: return
            }
        }
    }

    private func parseDefault() {
        advance() // default
        if case .word("namespace") = peek() { parseNamespace(isDefault: true) }
    }

    private func parseNamespace(isDefault: Bool) {
        advance() // namespace
        var prefix = ""
        if case let .word(name) = peek(), name != "=" { prefix = name
            advance()
        }
        expectSymbol("=")
        let uri = expectString()
        if isDefault { defaultNamespace = uri }
        if !prefix.isEmpty { namespaces[prefix] = uri }
    }

    private func parseDatatypes() {
        advance() // datatypes
        if case .word = peek() { advance() }
        expectSymbol("=")
        _ = expectString()
    }

    // MARK: Grammar body

    private func looksLikeGrammar() -> Bool {
        guard case let .word(word) = peek() else { return false }
        if word == "include" || word == "start" { return true }
        // A define is a word followed by one of =, |=, &=.
        if case let .symbol(symbol) = peek(1), symbol == "=" || symbol == "|=" || symbol == "&=" { return true }
        return false
    }

    private func parseGrammarBody() {
        while position < tokens.count, peek() != .symbol("}") {
            if case .word("include") = peek() {
                parseInclude()
            } else {
                parseDefine()
            }
        }
    }

    private func parseDefine() {
        guard case let .word(name) = peek() else { advance()
            return
        }
        advance()
        let combinator = expectAssignment()
        let pattern = parsePattern()
        if name == "start" {
            startPattern = combine(startPattern, pattern, combinator)
        } else {
            defines[name] = combine(defines[name], pattern, combinator)
        }
    }

    private func parseInclude() {
        advance() // include
        let href = expectString()
        if let text = loader(href), !visited.contains(href) {
            visited.insert(href)
            let sub = RNCParser(RNCLexer.tokens(text), loader: loader, visited: visited)
            sub.skipDeclarations()
            sub.parseGrammarBody()
            for (name, pattern) in sub.defines {
                defines[name] = pattern
            }
            if startPattern == nil { startPattern = sub.startPattern }
            visited = sub.visited
        }
        // An override block re-defines names after the include, overriding them.
        if peek() == .symbol("{") {
            advance()
            parseGrammarBody()
            expectSymbol("}")
        }
    }

    private func combine(_ existing: Pattern?, _ new: Pattern, _ combinator: String) -> Pattern {
        guard let existing else { return new }
        switch combinator {
        case "|=": return .choice(existing, new)
        case "&=": return .interleave(existing, new)
        default: return new
        }
    }

    // MARK: Patterns

    private func parsePattern() -> Pattern {
        var patterns = [parseParticle()]
        guard case let .symbol(operatorSymbol) = peek(), operatorSymbol == "," || operatorSymbol == "|" || operatorSymbol == "&" else {
            return patterns[0]
        }
        while peek() == .symbol(operatorSymbol) {
            advance()
            patterns.append(parseParticle())
        }
        return patterns.dropFirst().reduce(patterns[0]) { combinePatterns($0, $1, operatorSymbol) }
    }

    private func combinePatterns(_ lhs: Pattern, _ rhs: Pattern, _ operatorSymbol: String) -> Pattern {
        switch operatorSymbol {
        case "|": .choice(lhs, rhs)
        case "&": .interleave(lhs, rhs)
        default: .group(lhs, rhs)
        }
    }

    private func parseParticle() -> Pattern {
        let primary = parsePrimary()
        switch peek() {
        case .symbol("?"): advance()
            return .choice(primary, .empty)
        case .symbol("*"): advance()
            return .choice(.oneOrMore(primary), .empty)
        case .symbol("+"): advance()
            return .oneOrMore(primary)
        default: return primary
        }
    }

    private func parsePrimary() -> Pattern {
        guard case let .word(word) = peek() else { return parseNonWordPrimary() }
        if let leaf = leafKeyword(word) {
            advance()
            return leaf
        }
        return blockKeyword(word)
    }

    /// The keyword patterns that take no block and map to a constant.
    private func leafKeyword(_ word: String) -> Pattern? {
        switch word {
        case "text": .text
        case "empty": .empty
        case "notAllowed": .notAllowed
        case "string", "token": .data(PureXML.Schema.SimpleType(base: .string))
        default: nil
        }
    }

    /// The keyword patterns that introduce a block, reference, or external
    /// schema; a bare word falls through to a datatype or define reference.
    private func blockKeyword(_ word: String) -> Pattern {
        switch word {
        case "element": advance()
            return parseElement()
        case "attribute": advance()
            return parseAttribute()
        case "list": advance()
            return .list(parseBraced())
        case "mixed": advance()
            return .interleave(parseBraced(), .text)
        case "external": advance()
            return externalPattern(expectString())
        case "grammar": advance()
            return nestedGrammar()
        case "parent": advance()
            return .ref(wordValue())
        default: return wordPrimary(word)
        }
    }

    private func parseNonWordPrimary() -> Pattern {
        switch peek() {
        case let .string(value): advance()
            return .value(value)
        case .symbol("("): advance()
            let pattern = parsePattern()
            expectSymbol(")")
            return pattern
        default: advance()
            return .notAllowed
        }
    }

    /// A `:`-qualified word is a datatype (optionally with a parameter block or a
    /// value literal); a bare word is a reference to a define.
    private func wordPrimary(_ word: String) -> Pattern {
        advance()
        guard word.contains(":") else { return .ref(word) }
        let type = PureXML.Schema.BuiltinType(rawValue: strip(word)) ?? .string
        if peek() == .symbol("{") { skipBraces() }
        if case let .string(value) = peek() { advance()
            return .value(value)
        }
        return .data(PureXML.Schema.SimpleType(base: type))
    }

    private func parseElement() -> Pattern {
        let nameClass = parseNameClass(attribute: false)
        return .element(nameClass, parseBraced())
    }

    private func parseAttribute() -> Pattern {
        let nameClass = parseNameClass(attribute: true)
        return .attribute(nameClass, parseBraced())
    }

    private func parseBraced() -> Pattern {
        expectSymbol("{")
        let pattern = parsePattern()
        expectSymbol("}")
        return pattern
    }

    private func nestedGrammar() -> Pattern {
        expectSymbol("{")
        parseGrammarBody()
        expectSymbol("}")
        return startPattern ?? .notAllowed
    }

    private func externalPattern(_ href: String) -> Pattern {
        guard let text = loader(href), !visited.contains(href) else { return .notAllowed }
        visited.insert(href)
        let sub = RNCParser(RNCLexer.tokens(text), loader: loader, visited: visited)
        let (start, subDefines) = sub.parse()
        for (name, pattern) in subDefines {
            defines[name] = pattern
        }
        visited = sub.visited
        return start
    }
}

/// Name-class and token-stream helpers for ``RNCParser``.
private extension RNCParser {
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
        switch peek() {
        case .symbol("*"):
            advance()
            return .anyName
        case .symbol("("):
            advance()
            let nameClass = parseNameClass(attribute: attribute)
            expectSymbol(")")
            return nameClass
        case let .word(word):
            advance()
            return qualifiedName(word, attribute: attribute)
        default:
            advance()
            return .anyName
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

    private func peek(_ offset: Int = 0) -> RNCToken? {
        let index = position + offset
        return index < tokens.count ? tokens[index] : nil
    }

    @discardableResult
    private func advance() -> RNCToken? {
        defer { position += 1 }
        return peek()
    }

    private func wordValue() -> String {
        if case let .word(word) = peek() { advance()
            return word
        }
        return ""
    }

    private func expectAssignment() -> String {
        if case let .symbol(symbol) = peek(), symbol == "=" || symbol == "|=" || symbol == "&=" {
            advance()
            return symbol
        }
        return "="
    }

    private func expectSymbol(_ symbol: String) {
        if peek() == .symbol(symbol) { advance() }
    }

    private func expectString() -> String {
        if case let .string(value) = peek() { advance()
            return value
        }
        return ""
    }

    private func skipBraces() {
        guard peek() == .symbol("{") else { return }
        var depth = 0
        repeat {
            switch advance() {
            case .symbol("{"): depth += 1
            case .symbol("}"): depth -= 1
            default: break
            }
        } while depth > 0 && position < tokens.count
    }

    private func strip(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }
}

extension PureXML.Schema {
    /// Parses a RELAX NG schema in the compact syntax (RNC) into a start pattern
    /// and named `define` patterns, the same algebra the XML syntax compiles to.
    /// Supports element/attribute declarations with name classes and namespaces,
    /// the `,` `|` `&` combinators, `?` `*` `+` cardinality, `text`, `empty`,
    /// `notAllowed`, `list`, `mixed`, datatypes and value literals, grammars with
    /// `start` and named definitions (`=`, `|=`, `&=`), nested grammars, and
    /// `include` and `external` resolved through `loader`.
    enum RelaxNGCompactParser {
        static func parse(
            _ rnc: String,
            loader: @escaping (String) -> String? = { _ in nil },
        ) throws -> (start: Pattern, defines: [String: Pattern]) {
            RNCParser(RNCLexer.tokens(rnc), loader: loader).parse()
        }
    }
}
