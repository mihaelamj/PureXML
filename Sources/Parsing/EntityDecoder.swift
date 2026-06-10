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
