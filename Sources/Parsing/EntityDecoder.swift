extension PureXML.Parsing {
    /// Decodes XML references inside text and attribute values: the five
    /// predefined entities, decimal/hex character references, and declared
    /// internal general entities.
    ///
    /// Declared-entity expansion is the billion-laughs vector, so it is bounded:
    /// only characters produced by expansion count against a shared budget, and a
    /// set of in-progress entity names detects recursive references. Literal
    /// document text never consumes the budget.
    enum EntityDecoder {
        /// Decodes references in `raw`. `entities` is the declared internal-entity
        /// table (empty unless a DTD was processed). `budget` is the remaining
        /// expansion allowance, shared across the document and decremented as
        /// expansion produces characters.
        static func decode(
            _ raw: String,
            entities: [String: String],
            budget: inout Int,
            at mark: Mark,
        ) throws -> String {
            guard raw.contains("&") else { return raw }
            var expander = EntityExpander(entities: entities, mark: mark, budget: budget)
            try expander.expand(raw, visiting: [], counts: false)
            budget = expander.budget
            return expander.result
        }
    }
}

/// Content splicing (4.4.2 Included): a declared general entity whose
/// replacement text, directly or through entities it references, contains
/// markup must be reparsed as content, not included as character data. The
/// event reader uses these helpers to find such references in a text run, to
/// validate and budget the inclusion, and to splice the replacement back into
/// its character stream.
extension PureXML.Parsing.EntityDecoder {
    private static let predefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    /// A text run split at a markup-producing entity reference: the text
    /// before the reference, the entity name, and the unconsumed text after.
    struct MarkupSplit {
        let prefix: String
        let name: String
        let remainder: String
    }

    /// Splits `raw` at the first reference to a declared entity whose
    /// replacement produces markup. Nil when no such reference occurs and
    /// plain decoding suffices.
    static func splitAtMarkupEntity(_ raw: String, entities: [String: String]) -> MarkupSplit? {
        guard !entities.isEmpty else { return nil }
        var index = raw.startIndex
        while index < raw.endIndex, let amp = raw[index...].firstIndex(of: "&") {
            guard let semicolon = raw[amp...].firstIndex(of: ";") else { return nil }
            let name = String(raw[raw.index(after: amp) ..< semicolon])
            if !name.hasPrefix("#"), !predefined.contains(name), producesMarkup(name, entities: entities, visiting: []) {
                return MarkupSplit(
                    prefix: String(raw[..<amp]),
                    name: name,
                    remainder: String(raw[raw.index(after: semicolon)...]),
                )
            }
            index = raw.index(after: semicolon)
        }
        return nil
    }

    /// Validates and budgets one content inclusion of `name`, returning its
    /// replacement text for splicing: the replacement must reparse as balanced
    /// content (the reference-time WFC), the reference chain must not recurse,
    /// and the replacement's size counts against the amplification budget.
    static func includeForContent(
        _ name: String,
        entities: [String: String],
        budget: inout Int,
        at mark: PureXML.Parsing.Mark,
    ) throws -> String {
        guard let replacement = entities[name] else {
            throw PureXML.Parsing.ParseError.undefinedEntity(name: name, mark)
        }
        if PureXML.Parsing.EntityReplacementGrammar.violation(inValue: replacement) != nil {
            throw PureXML.Parsing.ParseError.invalidReference("&\(name);", mark)
        }
        try checkRecursion(name, entities: entities, visiting: [name], at: mark)
        guard budget >= replacement.count else {
            throw PureXML.Parsing.ParseError.amplificationLimitExceeded(mark)
        }
        budget -= replacement.count
        return replacement
    }

    /// Whether `name`'s replacement contains markup, directly or transitively.
    private static func producesMarkup(_ name: String, entities: [String: String], visiting: Set<String>) -> Bool {
        guard !visiting.contains(name), let replacement = entities[name] else { return false }
        if replacement.contains("<") { return true }
        return declaredReferences(in: replacement).contains {
            producesMarkup($0, entities: entities, visiting: visiting.union([name]))
        }
    }

    private static func checkRecursion(
        _ name: String,
        entities: [String: String],
        visiting: Set<String>,
        at mark: PureXML.Parsing.Mark,
    ) throws {
        guard let replacement = entities[name] else { return }
        for reference in declaredReferences(in: replacement) {
            guard !visiting.contains(reference) else {
                throw PureXML.Parsing.ParseError.recursiveEntity(name: reference, mark)
            }
            try checkRecursion(reference, entities: entities, visiting: visiting.union([reference]), at: mark)
        }
    }

    /// The declared-entity names referenced in `text`: `&name;` forms that are
    /// neither predefined nor character references. References inside CDATA
    /// sections are shielded and not counted.
    private static func declaredReferences(in text: String) -> [String] {
        var names: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("<![CDATA[") {
                var cursor = text.index(index, offsetBy: 9)
                while cursor < text.endIndex, !text[cursor...].hasPrefix("]]>") {
                    cursor = text.index(after: cursor)
                }
                index = cursor < text.endIndex ? text.index(cursor, offsetBy: 3) : text.endIndex
                continue
            }
            guard text[index] == "&" else {
                index = text.index(after: index)
                continue
            }
            guard let semicolon = text[index...].firstIndex(of: ";") else { return names }
            let name = String(text[text.index(after: index) ..< semicolon])
            if !name.hasPrefix("#"), !predefined.contains(name) {
                names.append(name)
            }
            index = text.index(after: semicolon)
        }
        return names
    }
}

/// Carries the mutable state of one decode pass (output and remaining budget) so
/// the recursive expansion stays a few small methods. File-scope and private.
///
/// Two independent bounds defend against expansion attacks: the character
/// `budget` caps total output, and the `visiting` set caps recursion depth,
/// since each entity name may appear at most once per chain, the expansion
/// depth is bounded by the number of declared entities (a cycle is an error).
private struct EntityExpander {
    let entities: [String: String]
    let mark: PureXML.Parsing.Mark
    var budget: Int
    var result = ""

    mutating func expand(_ raw: String, visiting: Set<String>, counts: Bool) throws {
        var iterator = raw.startIndex
        while iterator < raw.endIndex {
            let character = raw[iterator]
            // A CDATA section inside replacement text shields its content from
            // reference recognition: copy it verbatim through the terminator.
            if character == "<", raw[iterator...].hasPrefix("<![CDATA[") {
                let openEnd = raw.index(iterator, offsetBy: 9)
                var end = raw.endIndex
                var cursor = openEnd
                while cursor < raw.endIndex {
                    if raw[cursor...].hasPrefix("]]>") {
                        end = raw.index(cursor, offsetBy: 3)
                        break
                    }
                    cursor = raw.index(after: cursor)
                }
                for verbatim in raw[iterator ..< end] {
                    try append(verbatim, counts: counts)
                }
                iterator = end
                continue
            }
            guard character == "&" else {
                try append(character, counts: counts)
                iterator = raw.index(after: iterator)
                continue
            }
            guard let semicolon = raw[iterator...].firstIndex(of: ";") else {
                throw PureXML.Parsing.ParseError.invalidReference(String(raw[iterator...]), mark)
            }
            let body = String(raw[raw.index(after: iterator) ..< semicolon])
            try resolve(body, visiting: visiting, counts: counts)
            iterator = raw.index(after: semicolon)
        }
    }

    private mutating func resolve(_ body: String, visiting: Set<String>, counts: Bool) throws {
        if let predefined = Self.predefinedValue(body) {
            try append(predefined, counts: counts)
            return
        }
        if body.hasPrefix("#") {
            try append(Self.characterReference(body, at: mark), counts: counts)
            return
        }
        guard let replacement = entities[body] else {
            throw PureXML.Parsing.ParseError.undefinedEntity(name: body, mark)
        }
        guard !visiting.contains(body) else {
            throw PureXML.Parsing.ParseError.recursiveEntity(name: body, mark)
        }
        // The replacement-text well-formedness constraint binds here, at the
        // reference: the included text must reparse as balanced content in
        // isolation (so '&' alone, an incomplete reference, or tags spanning
        // the entity boundary are rejected on use, not on declaration).
        if PureXML.Parsing.EntityReplacementGrammar.violation(inValue: replacement) != nil {
            throw PureXML.Parsing.ParseError.invalidReference("&\(body);", mark)
        }
        // Expanding a declared entity: every produced character now counts against
        // the amplification budget.
        try expand(replacement, visiting: visiting.union([body]), counts: true)
    }

    private mutating func append(_ character: Character, counts: Bool) throws {
        if counts {
            guard budget > 0 else {
                throw PureXML.Parsing.ParseError.amplificationLimitExceeded(mark)
            }
            budget -= 1
        }
        result.append(character)
    }

    private static func predefinedValue(_ body: String) -> Character? {
        switch body {
        case "amp": "&"
        case "lt": "<"
        case "gt": ">"
        case "quot": "\""
        case "apos": "'"
        default: nil
        }
    }

    private static func characterReference(_ body: String, at mark: PureXML.Parsing.Mark) throws -> Character {
        let digits = String(body.dropFirst())
        // XML 1.0: only lowercase 'x' introduces a hex reference, and the
        // referenced code point must be a valid XML Char (rejecting NUL, bare
        // control characters, surrogates, and U+FFFE/U+FFFF).
        let scalarValue: UInt32? = if digits.hasPrefix("x") {
            UInt32(digits.dropFirst(), radix: 16)
        } else if digits.hasPrefix("X") {
            nil
        } else {
            UInt32(digits, radix: 10)
        }
        guard let value = scalarValue, let scalar = Unicode.Scalar(value),
              PureXML.Parsing.XMLCharacter.isChar(scalar)
        else {
            throw PureXML.Parsing.ParseError.invalidReference("&\(body);", mark)
        }
        return Character(scalar)
    }
}
