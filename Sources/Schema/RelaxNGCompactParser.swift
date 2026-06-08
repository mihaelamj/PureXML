typealias RNCToken = PureXML.Schema.RNCToken
typealias RNCLexer = PureXML.Schema.RNCLexer

/// A recursive-descent parser from the token stream to the pattern algebra.
/// Module-internal; the only entry point is ``PureXML/Schema/RelaxNGCompactParser``.
final class RNCParser {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass

    let tokens: [RNCToken]
    var position = 0
    let loader: (String) -> String?
    private(set) var defines: [String: Pattern] = [:]
    var startPattern: Pattern?
    var defaultNamespace = ""
    var namespaces: [String: String] = [:]
    var visited: Set<String>

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
}

// MARK: Declarations, grammar, and patterns

extension RNCParser {
    private func skipDeclarations() {
        while true {
            skipAnnotation()
            guard case let .word(keyword) = peek() else { return }
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
            skipAnnotation()
            guard position < tokens.count, peek() != .symbol("}") else { break }
            parseGrammarItem()
        }
    }

    private func parseGrammarItem() {
        if case .word("include") = peek() {
            parseInclude()
        } else if case .word("div") = peek(), peek(1) == .symbol("{") {
            parseDiv()
        } else {
            parseDefine()
        }
    }

    /// A `div { ... }` grouping is transparent: it scopes annotations in the
    /// full syntax but contributes its defines and `start` directly here.
    private func parseDiv() {
        advance() // div
        expectSymbol("{")
        parseGrammarBody()
        expectSymbol("}")
    }

    /// Skips a leading `[ ... ]` documentation/grammar annotation (balanced over
    /// nested brackets). Annotations carry no schema semantics, so they are
    /// dropped wherever they may appear: before a define, or before a pattern.
    private func skipAnnotation() {
        while peek() == .symbol("[") {
            advance()
            var depth = 1
            while position < tokens.count, depth > 0 {
                let token = advance()
                if token == .symbol("[") { depth += 1 } else if token == .symbol("]") { depth -= 1 }
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
        skipAnnotation()
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
            // A bare string literal is shorthand for a `token`-typed value.
            return .value(PureXML.Schema.SimpleType(base: .token), concatenated(value))
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
        var facets = PureXML.Schema.Facets()
        if peek() == .symbol("{") { parseParams(into: &facets) }
        if case let .string(value) = peek() { advance()
            return .value(PureXML.Schema.SimpleType(base: type), concatenated(value))
        }
        return .data(PureXML.Schema.SimpleType(base: type, facets: facets))
    }

    /// Parses a datatype parameter block `{ name = "value" ... }` into facets (the
    /// compact-syntax form of `<param>`).
    private func parseParams(into facets: inout PureXML.Schema.Facets) {
        advance() // {
        while position < tokens.count, peek() != .symbol("}") {
            guard case let .word(name) = peek() else { advance()
                continue
            }
            advance()
            if peek() == .symbol("=") { advance() }
            guard case let .string(value) = peek() else { continue }
            advance()
            PureXML.Schema.RelaxNGFacets.apply(name, value, into: &facets)
        }
        if peek() == .symbol("}") { advance() }
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
