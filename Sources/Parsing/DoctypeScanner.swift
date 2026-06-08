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
/// remaining parameter-entity expansion budget. File-scope and private: an
/// internal detail of ``PureXML/Parsing/DoctypeScanner``.
private struct DTDScanner {
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
    private let maxDepth = 40

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
        doctype.externalSubset = parseExternalID(&reader)
        reader.skipSpace()
        if reader.consume("[") {
            try scanDeclarations(&reader, depth: 0, terminatedByBracket: true, at: mark)
        }
        reader.skipSpace()
        guard reader.consume(">") else {
            throw ParseError.unterminatedTag(mark)
        }
        loadExternalSubset(at: mark)
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
    /// internal subset is scanned first and wins).
    private mutating func loadExternalSubset(at mark: Mark) {
        guard let id = doctype.externalSubset, let text = resolver.resolveExternalSubset(id) else {
            return
        }
        var sub = Reader(text)
        try? scanDeclarations(&sub, depth: 1, terminatedByBracket: false, at: mark)
    }

    private mutating func scanDeclarations(
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
            } else {
                scanMarkupDeclaration(&reader)
            }
        }
    }

    private mutating func scanMarkupDeclaration(_ reader: inout Reader) {
        if reader.matches("<!ENTITY") {
            scanEntityDeclaration(&reader)
        } else if reader.matches("<!ELEMENT") {
            scanElementDeclaration(&reader)
        } else if reader.matches("<!ATTLIST") {
            scanAttributeListDeclaration(&reader)
        } else if reader.matches("<!--") {
            skip(&reader, until: "-->")
        } else if reader.matches("<?") {
            skip(&reader, until: "?>")
        } else if reader.matches("<![") {
            // Conditional section (INCLUDE/IGNORE): skipped as a unit for now.
            skip(&reader, until: "]]>")
        } else if reader.matches("<!") {
            skip(&reader, until: ">")
        } else {
            reader.advance()
        }
    }

    /// Handles a bare `%name;` between declarations by injecting the parameter
    /// entity's replacement text and scanning its declarations. Bounded by depth
    /// and the expansion budget.
    private mutating func scanParameterReference(_ reader: inout Reader, depth: Int, at mark: Mark) throws {
        reader.consume("%")
        let name = scanName(&reader)
        reader.consume(";")
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

    private mutating func scanEntityDeclaration(_ reader: inout Reader) {
        reader.consume("<!ENTITY")
        reader.skipSpace()
        let isParameter = reader.consume("%")
        if isParameter {
            reader.skipSpace()
        }
        let name = scanName(&reader)
        reader.skipSpace()
        if let value = scanLiteral(&reader) {
            skip(&reader, until: ">")
            storeEntity(name: name, value: expandParameterReferences(value), isParameter: isParameter)
            return
        }
        let id = parseExternalID(&reader)
        skip(&reader, until: ">")
        // Internal parameter entities and internal general entities are stored;
        // external general entities record their identifier for the resolver;
        // external parameter entities are not loaded in this build.
        if let id, !isParameter, !name.isEmpty, doctype.externalEntities[name] == nil {
            doctype.externalEntities[name] = id
        }
    }

    private mutating func storeEntity(name: String, value: String, isParameter: Bool) {
        guard !name.isEmpty else { return }
        if isParameter {
            if doctype.parameterEntities[name] == nil {
                doctype.parameterEntities[name] = value
            }
        } else if doctype.entities[name] == nil {
            doctype.entities[name] = value
        }
    }

    private mutating func scanElementDeclaration(_ reader: inout Reader) {
        reader.consume("<!ELEMENT")
        reader.skipSpace()
        let name = scanName(&reader)
        reader.skipSpace()
        let model = expandParameterReferences(readUntilClose(&reader))
        guard !name.isEmpty, doctype.elementModels[name] == nil else { return }
        doctype.elementModels[name] = model.trimmingXMLWhitespace()
    }

    private mutating func scanAttributeListDeclaration(_ reader: inout Reader) {
        reader.consume("<!ATTLIST")
        reader.skipSpace()
        let name = scanName(&reader)
        let body = expandParameterReferences(readUntilClose(&reader))
        guard !name.isEmpty else { return }
        let trimmed = body.trimmingXMLWhitespace()
        if let existing = doctype.attributeLists[name] {
            doctype.attributeLists[name] = "\(existing) \(trimmed)"
        } else {
            doctype.attributeLists[name] = trimmed
        }
    }

    /// Replaces `%name;` references with their (already-expanded) parameter-entity
    /// values. Undefined references are left literal. A single forward pass is
    /// enough because each value was expanded against the entities defined before
    /// it, so no reference can reach a later definition.
    private func expandParameterReferences(_ raw: String) -> String {
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

    private func scanLiteral(_ reader: inout Reader) -> String? {
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

    private func scanName(_ reader: inout Reader) -> String {
        var name = ""
        while let character = reader.peek(), character.isXMLNameContinuation {
            name.append(character)
            reader.advance()
        }
        return name
    }

    private func skip(_ reader: inout Reader, until terminator: String) {
        while reader.peek() != nil, !reader.matches(terminator) {
            reader.advance()
        }
        reader.consume(terminator)
    }
}
