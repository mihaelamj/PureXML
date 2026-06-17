extension PureXML.Schema.XSDParser {
    /// Validity of an identity constraint's `selector`/`field` `xpath` against the
    /// XSD 1.0 restricted-XPath subset (Part 1, 3.11.6), a small grammar far
    /// narrower than full XPath:
    ///
    ///     Selector ::= Path ( '|' Path )*
    ///     Path     ::= ('.//')? Step ( '/' Step )*
    ///     Step     ::= '.' | NameTest | 'child' '::' NameTest
    ///     NameTest ::= QName | '*' | NCName ':' '*'
    ///     Field    ::= Path ( '|' Path )*  (a field's last step may be an attribute:
    ///                  '@' NameTest or 'attribute' '::' NameTest)
    ///
    /// So no predicates (`[...]`), no axes beyond `child::`/`attribute::`, no absolute
    /// or interior `//` (only a leading `.//`), and `@`/`attribute::` only as a
    /// field's trailing step. Being a subset of XPath syntax, whitespace is allowed
    /// between tokens (so `child :: a` and `. //.` are valid), but `//` must be two
    /// adjacent slashes and a name test's own `:` admits no whitespace (so `tid : *`
    /// is not). The xpath was stored raw and compiled lazily with `try?`, so a
    /// malformed one was silently accepted; it is now rejected at compile time.
    static func identityXPathErrors(_ node: XSDTree, local: String) -> [String] {
        guard local == "selector" || local == "field",
              let xpath = PureXML.Schema.XSDNode.attribute(node, "xpath")
        else { return [] }
        if !validXPath(xpath, isField: local == "field") {
            return ["the \(local) xpath '\(xpath)' is not a valid identity-constraint path"]
        }
        // Every namespace prefix a name test uses must be declared in scope; the
        // implicit `xml` prefix is always bound. An unbound prefix is invalid.
        let bindings = namespaceBindingsInScope(of: node, defaultBindings: [:])
        for prefix in xpathNameTestPrefixes(xpath) where prefix != "xml" && bindings[prefix] == nil {
            return ["the \(local) xpath '\(xpath)' uses the undeclared namespace prefix '\(prefix)'"]
        }
        return []
    }

    /// The set of namespace prefixes used in the name tests of a (syntactically
    /// valid) identity-constraint xpath. A name test is `prefix:local` or
    /// `prefix:*`; an unprefixed name, `*`, `.`, or an axis keyword has no prefix.
    private static func xpathNameTestPrefixes(_ xpath: String) -> [String] {
        guard let tokens = tokenize(xpath) else { return [] }
        var prefixes: [String] = []
        for case let .name(name) in tokens {
            guard let colon = name.firstIndex(of: ":") else { continue }
            let prefix = String(name[name.startIndex ..< colon])
            if !prefix.isEmpty { prefixes.append(prefix) }
        }
        return prefixes
    }

    private enum XPathToken: Equatable {
        case slash, doubleSlash, axis, atSign, pipe, dot, star, name(String)
    }

    private static func validXPath(_ xpath: String, isField: Bool) -> Bool {
        guard let tokens = tokenize(xpath) else { return false }
        let paths = tokens.split(separator: .pipe, omittingEmptySubsequences: false)
        guard !paths.isEmpty else { return false }
        return paths.allSatisfy { validPath(Array($0), isField: isField) }
    }

    /// Lexes the restricted-XPath token stream, skipping inter-token whitespace, or
    /// nil on an unlexable character (a predicate bracket, a parenthesis, a `:` that
    /// is neither part of a name test nor a `::` axis).
    private static func tokenize(_ xpath: String) -> [XPathToken]? {
        var tokens: [XPathToken] = []
        let characters = Array(xpath)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if let simple = simpleToken(character) {
                tokens.append(simple)
                index += 1
            } else if character == "/" {
                let double = index + 1 < characters.count && characters[index + 1] == "/"
                tokens.append(double ? .doubleSlash : .slash)
                index += double ? 2 : 1
            } else if character == ":" {
                guard index + 1 < characters.count, characters[index + 1] == ":" else { return nil }
                tokens.append(.axis)
                index += 2
            } else if isNameStart(character) {
                tokens.append(.name(readName(characters, &index)))
            } else {
                return nil
            }
        }
        return tokens
    }

    /// The single-character tokens that need no lookahead.
    private static func simpleToken(_ character: Character) -> XPathToken? {
        switch character {
        case "|": .pipe
        case "@": .atSign
        case ".": .dot
        case "*": .star
        default: nil
        }
    }

    /// Reads a name test starting at `index`: a name run, optionally glued (no
    /// whitespace) to `:` and a second name run or `*`, leaving a following `::` for
    /// the lexer to read as an axis.
    private static func readName(_ characters: [Character], _ index: inout Int) -> String {
        var name = takeNameRun(characters, &index)
        if index + 1 < characters.count, characters[index] == ":", characters[index + 1] != ":" {
            index += 1
            if characters[index] == "*" {
                name += ":*"
                index += 1
            } else {
                name += ":" + takeNameRun(characters, &index)
            }
        }
        return name
    }

    private static func takeNameRun(_ characters: [Character], _ index: inout Int) -> String {
        var run = ""
        while index < characters.count, isNameContinuation(characters[index]) {
            run.append(characters[index])
            index += 1
        }
        return run
    }

    /// A name-test character set matching XML 1.0 `NameChar` (minus `:`, which is
    /// glue or an axis here), so the lexer admits exactly the names `Lexical.isNCName`
    /// will validate, including non-ASCII NCName characters Swift's `isLetter` misses.
    private static func isNameContinuation(_ character: Character) -> Bool {
        character != ":" && character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar)
    }

    /// A name-test start character: XML 1.0 `NameStartChar` (minus `:`); the first
    /// scalar must start a name and any later scalars (a combining grapheme) be name
    /// characters.
    private static func isNameStart(_ character: Character) -> Bool {
        guard character != ":", let first = character.unicodeScalars.first,
              PureXML.Parsing.XMLCharacter.isNameStart(first)
        else { return false }
        return character.unicodeScalars.dropFirst().allSatisfy(PureXML.Parsing.XMLCharacter.isNameChar)
    }

    /// An optional leading `.//`, then `/`-separated steps; `//` is rejected except
    /// as that leading prefix, and an empty step (a leading/trailing/doubled `/`)
    /// fails.
    private static func validPath(_ tokens: [XPathToken], isField: Bool) -> Bool {
        guard !tokens.isEmpty else { return false }
        var body = tokens[...]
        if body.first == .dot, body.dropFirst().first == .doubleSlash {
            body = body.dropFirst(2)
            guard !body.isEmpty else { return false }
        }
        var steps: [[XPathToken]] = [[]]
        for token in body {
            switch token {
            case .slash: steps.append([])
            case .doubleSlash: return false
            default: steps[steps.count - 1].append(token)
            }
        }
        return steps.enumerated().allSatisfy { index, step in
            validStep(step, isField: isField, isLast: index == steps.count - 1)
        }
    }

    /// A single step: `.`, a name test, a `child::` axis step, or (only as a field's
    /// last step) an `@`/`attribute::` attribute step.
    private static func validStep(_ step: [XPathToken], isField: Bool, isLast: Bool) -> Bool {
        switch step.first {
        case .dot where step.count == 1:
            true
        case .atSign:
            isField && isLast && nameTest(Array(step.dropFirst()))
        case .name("child") where step.count > 1 && step[1] == .axis:
            nameTest(Array(step.dropFirst(2)))
        case .name("attribute") where step.count > 1 && step[1] == .axis:
            isField && isLast && nameTest(Array(step.dropFirst(2)))
        default:
            nameTest(step)
        }
    }

    /// A single name-test token: `*`, a QName, or `NCName ':' '*'`.
    private static func nameTest(_ tokens: [XPathToken]) -> Bool {
        guard tokens.count == 1 else { return false }
        switch tokens[0] {
        case .star:
            return true
        case let .name(value):
            return validNameTestName(value)
        default:
            return false
        }
    }

    private static func validNameTestName(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return PureXML.Schema.Lexical.isNCName(value)
        case 2:
            let localPart = String(parts[1])
            return PureXML.Schema.Lexical.isNCName(String(parts[0]))
                && (localPart == "*" || PureXML.Schema.Lexical.isNCName(localPart))
        default:
            return false
        }
    }
}
