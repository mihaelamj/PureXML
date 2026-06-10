extension PureXML.Parsing {
    /// Consumes a `<!DOCTYPE ...>` declaration.
    ///
    /// When DTD processing is disabled (the default), the whole declaration is
    /// refused, which keeps the XXE and entity-expansion threat classes closed.
    /// When enabled, it honors internal general entities, internal parameter
    /// entities (`<!ENTITY % name "value">`, expanded within the subset), element
    /// and attribute-list declarations, and records external entity and external
    /// subset identifiers. External text is loaded only through an injected
    /// ``EntityResolver``; with the default refusing resolver nothing external is
    /// read. Thin wrapper over the file-scope ``DTDScanner`` state machine.
    enum DoctypeScanner {
        static func scan(
            _ reader: inout Reader,
            limits: Limits,
            resolver: EntityResolver = .refusing,
        ) throws -> DocumentType {
            let mark = reader.mark
            guard limits.allowDoctype else {
                throw ParseError.unsupportedDoctype(mark)
            }
            var scanner = DTDScanner(limits: limits, resolver: resolver)
            return try scanner.scan(&reader, at: mark)
        }
    }
}

/// The mutable state of one DTD scan: the document type being built and the
/// remaining parameter-entity expansion budget. An internal detail of
/// ``PureXML/Parsing/DoctypeScanner``; the strict declaration grammar lives in
/// DoctypeScannerStrict.swift.
struct DTDScanner {
    typealias Reader = PureXML.Parsing.Reader
    typealias Mark = PureXML.Parsing.Mark
    typealias ParseError = PureXML.Parsing.ParseError
    typealias ExternalID = PureXML.Parsing.ExternalID

    let limits: PureXML.Parsing.Limits
    let resolver: PureXML.Parsing.EntityResolver
    var doctype = PureXML.Parsing.DocumentType()
    var parameterBudget: Int
    /// Bounds parameter-entity injection recursion (modularized DTDs nest, but
    /// only a little); deeper references are ignored rather than trapping.
    let maxDepth = 40

    init(limits: PureXML.Parsing.Limits, resolver: PureXML.Parsing.EntityResolver) {
        self.limits = limits
        self.resolver = resolver
        parameterBudget = limits.maxEntityExpansion
    }

    mutating func scan(_ reader: inout Reader, at mark: Mark) throws -> PureXML.Parsing.DocumentType {
        reader.consume("<!DOCTYPE")
        reader.skipSpace()
        _ = scanName(&reader)
        reader.skipSpace()
        doctype.externalSubset = try parseStrictExternalID(&reader, requireSystem: true, at: mark)
        reader.skipSpace()
        if reader.consume("[") {
            try scanDeclarations(&reader, depth: 0, terminatedByBracket: true, at: mark)
        }
        reader.skipSpace()
        guard reader.consume(">") else {
            throw ParseError.unterminatedTag(mark)
        }
        try loadExternalSubset(at: mark)
        resolveExternalEntities()
        return doctype
    }

    /// Folds declared external general entities into the general-entity table by
    /// asking the resolver for their replacement text. A refused (nil) entity
    /// stays undeclared, so a reference to it errors and the default refusing
    /// resolver keeps XXE closed.
    private mutating func resolveExternalEntities() {
        for (name, id) in doctype.externalEntities where doctype.entities[name] == nil {
            if let text = resolver.resolveEntity(name, id) {
                doctype.entities[name] = text
            }
        }
    }

    /// Loads the external subset through the resolver, if one is configured and
    /// returns text. External declarations never override internal ones (the
    /// internal subset is scanned first and wins). A grammar violation in the
    /// external subset is a well-formedness error of the document, so errors
    /// propagate. The subset may open with a text declaration (production 77).
    private mutating func loadExternalSubset(at mark: Mark) throws {
        guard let id = doctype.externalSubset, let text = resolver.resolveExternalSubset(id) else {
            return
        }
        var sub = Reader(text)
        try scanTextDeclaration(&sub, at: mark)
        try scanDeclarations(&sub, depth: 1, terminatedByBracket: false, at: mark)
    }

    mutating func scanDeclarations(
        _ reader: inout Reader,
        depth: Int,
        terminatedByBracket: Bool,
        at mark: Mark,
    ) throws {
        while true {
            reader.skipSpace()
            guard let character = reader.peek() else {
                if terminatedByBracket {
                    throw ParseError.unsupportedDoctype(mark)
                }
                return
            }
            if terminatedByBracket, reader.consume("]") {
                return
            }
            if character == "%" {
                try scanParameterReference(&reader, depth: depth, at: mark)
            } else if reader.matches("<![") {
                try scanConditionalSection(&reader, depth: depth, at: mark)
            } else if character == "<" {
                try scanMarkupDeclaration(&reader)
            } else {
                // Only markup declarations, PE references, and whitespace may
                // appear between declarations.
                throw ParseError.malformedDeclaration(reader.mark)
            }
        }
    }

    private mutating func scanMarkupDeclaration(_ reader: inout Reader) throws {
        if reader.matches("<!ENTITY") {
            try scanEntityDeclaration(&reader)
        } else if reader.matches("<!ELEMENT") {
            try scanElementDeclaration(&reader)
        } else if reader.matches("<!ATTLIST") {
            try scanAttributeListDeclaration(&reader)
        } else if reader.matches("<!NOTATION") {
            try scanNotationDeclaration(&reader)
        } else if reader.matches("<!--") {
            skip(&reader, until: "-->")
        } else if reader.matches("<?") {
            // The reserved target 'xml' may not appear as a PI in the subset.
            let mark = reader.mark
            reader.consume("<?")
            let target = scanName(&reader)
            if target.lowercased() == "xml" {
                throw ParseError.reservedProcessingInstructionTarget(mark)
            }
            skip(&reader, until: "?>")
        } else {
            // Any other construct here (an unknown or lowercase declaration
            // keyword, space after '<!', a DOCTYPE inside a subset, a bare '<')
            // is not well-formed.
            throw ParseError.malformedDeclaration(reader.mark)
        }
    }

    /// Handles a bare `%name;` between declarations by injecting the parameter
    /// entity's replacement text and scanning its declarations. Bounded by depth
    /// and the expansion budget.
    private mutating func scanParameterReference(_ reader: inout Reader, depth: Int, at mark: Mark) throws {
        let refMark = reader.mark
        reader.consume("%")
        let name = scanName(&reader)
        // PEReference is '%' Name ';' exactly: no space after '%' (an empty
        // name) and the semicolon must follow the name directly.
        guard !name.isEmpty, reader.consume(";") else {
            throw ParseError.invalidReference("%\(name)", refMark)
        }
        guard depth < maxDepth, let replacement = doctype.parameterEntities[name] else {
            return
        }
        guard parameterBudget >= replacement.count else {
            return
        }
        parameterBudget -= replacement.count
        var sub = Reader(replacement)
        try scanDeclarations(&sub, depth: depth + 1, terminatedByBracket: false, at: mark)
    }

    /// Files an external entity declaration by kind: an `NDATA` entity is unparsed
    /// (recorded with its notation); an external general entity records its
    /// identifier for the resolver; an external parameter entity is loaded through
    /// the resolver so its replacement text is available for `%name;` expansion
    /// (the default refusing resolver loads nothing, keeping XXE closed).
    mutating func storeExternalEntity(name: String, id: ExternalID, isParameter: Bool, notation: String?) {
        if let notation, !notation.isEmpty, !isParameter {
            if doctype.unparsedEntities[name] == nil {
                doctype.unparsedEntities[name] = PureXML.Parsing.UnparsedEntity(id: id, notation: notation)
            }
        } else if isParameter {
            if doctype.parameterEntities[name] == nil, let text = resolver.resolveExternalSubset(id) {
                doctype.parameterEntities[name] = expandParameterReferences(text)
            }
        } else if doctype.externalEntities[name] == nil {
            doctype.externalEntities[name] = id
        }
    }

    /// `<!NOTATION S Name S (ExternalID | PublicID) S? '>'` (production 82):
    /// the identifier is required and nothing may follow it but whitespace.
    private mutating func scanNotationDeclaration(_ reader: inout Reader) throws {
        let mark = reader.mark
        reader.consume("<!NOTATION")
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.malformedDeclaration(mark)
        }
        reader.skipSpace()
        let name = try scanStrictName(&reader, at: mark)
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.malformedDeclaration(mark)
        }
        reader.skipSpace()
        guard let id = try parseStrictExternalID(&reader, requireSystem: false, at: mark) else {
            throw ParseError.malformedDeclaration(mark)
        }
        reader.skipSpace()
        guard reader.consume(">") else {
            throw ParseError.malformedDeclaration(mark)
        }
        if doctype.notations[name] == nil {
            doctype.notations[name] = id
        }
    }

    mutating func storeEntity(name: String, value: String, isParameter: Bool) {
        guard !name.isEmpty else { return }
        if isParameter {
            if doctype.parameterEntities[name] == nil {
                doctype.parameterEntities[name] = value
            }
        } else if doctype.entities[name] == nil {
            doctype.entities[name] = value
        }
    }

    private mutating func scanElementDeclaration(_ reader: inout Reader) throws {
        let mark = reader.mark
        reader.consume("<!ELEMENT")
        guard reader.peek()?.isWhitespace == true else {
            throw PureXML.Parsing.ParseError.invalidContentModel(element: "", mark)
        }
        reader.skipSpace()
        let name = scanName(&reader)
        guard reader.peek()?.isWhitespace == true else {
            throw PureXML.Parsing.ParseError.invalidContentModel(element: name, mark)
        }
        reader.skipSpace()
        let model = expandParameterReferences(readUntilClose(&reader)).trimmingXMLWhitespace()
        guard PureXML.Parsing.DTDContentModelGrammar.isValid(model) else {
            throw PureXML.Parsing.ParseError.invalidContentModel(element: name, mark)
        }
        guard !name.isEmpty, doctype.elementModels[name] == nil else { return }
        doctype.elementModels[name] = model
    }

    private mutating func scanAttributeListDeclaration(_ reader: inout Reader) throws {
        let mark = reader.mark
        reader.consume("<!ATTLIST")
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.invalidAttributeListDeclaration(mark)
        }
        reader.skipSpace()
        let name = scanName(&reader)
        guard !name.isEmpty else {
            throw ParseError.invalidAttributeListDeclaration(mark)
        }
        let body = expandParameterReferences(readUntilClose(&reader))
        guard let defaults = PureXML.Parsing.DTDAttListGrammar.defaultValues(body) else {
            throw ParseError.invalidAttributeListDeclaration(mark)
        }
        for value in defaults {
            try validateDefaultValueReferences(value, at: mark)
        }
        let trimmed = body.trimmingXMLWhitespace()
        if let existing = doctype.attributeLists[name] {
            doctype.attributeLists[name] = "\(existing) \(trimmed)"
        } else {
            doctype.attributeLists[name] = trimmed
        }
    }
}

extension DTDScanner {
    /// Replaces `%name;` references with their (already-expanded) parameter-entity
    /// values. Undefined references are left literal. A single forward pass is
    /// enough because each value was expanded against the entities defined before
    /// it, so no reference can reach a later definition.
    func expandParameterReferences(_ raw: String) -> String {
        guard raw.contains("%") else { return raw }
        var result = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            guard character == "%", let semicolon = raw[index...].firstIndex(of: ";") else {
                result.append(character)
                index = raw.index(after: index)
                continue
            }
            let name = String(raw[raw.index(after: index) ..< semicolon])
            result += doctype.parameterEntities[name] ?? "%\(name);"
            index = raw.index(after: semicolon)
        }
        return result
    }

    private func parseExternalID(_ reader: inout Reader) -> ExternalID? {
        if reader.consume("SYSTEM") {
            reader.skipSpace()
            guard let systemID = scanLiteral(&reader) else { return nil }
            return ExternalID(systemID: systemID)
        }
        if reader.consume("PUBLIC") {
            reader.skipSpace()
            guard let publicID = scanLiteral(&reader) else { return nil }
            reader.skipSpace()
            let systemID = scanLiteral(&reader) ?? ""
            return ExternalID(publicID: publicID, systemID: systemID)
        }
        return nil
    }

    func scanLiteral(_ reader: inout Reader) -> String? {
        guard let quote = reader.peek(), quote == "\"" || quote == "'" else { return nil }
        reader.advance()
        var value = ""
        while let character = reader.peek(), character != quote {
            value.append(character)
            reader.advance()
        }
        reader.consume(String(quote))
        return value
    }

    private func readUntilClose(_ reader: inout Reader) -> String {
        var text = ""
        while let character = reader.peek(), character != ">" {
            text.append(character)
            reader.advance()
        }
        reader.consume(">")
        return text
    }

    func scanName(_ reader: inout Reader) -> String {
        var name = ""
        while let character = reader.peek(), character.isXMLNameContinuation {
            name.append(character)
            reader.advance()
        }
        return name
    }

    func skip(_ reader: inout Reader, until terminator: String) {
        while reader.peek() != nil, !reader.matches(terminator) {
            reader.advance()
        }
        reader.consume(terminator)
    }
}
