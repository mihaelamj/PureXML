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
            standalone: Bool = false,
            documentVersion: String? = nil,
        ) throws -> DocumentType {
            let mark = reader.mark
            guard limits.allowDoctype else {
                throw ParseError.unsupportedDoctype(mark)
            }
            var scanner = DTDScanner(limits: limits, resolver: resolver, standalone: standalone, documentVersion: documentVersion)
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
    /// Whether the document declared standalone='yes', which makes an
    /// undeclared-entity reference a well-formedness error rather than a
    /// validity finding (WFC vs VC: Entity Declared).
    let standalone: Bool
    /// The document's XML version: an external entity may not declare a
    /// higher version in its text declaration (errata E38).
    let documentVersion: String
    var doctype = PureXML.Parsing.DocumentType()
    /// True while scanning the external subset, so declarations record their
    /// origin (the standalone validity constraints depend on it).
    var inExternalContext = false
    /// External parameter entities that were declared but not loaded (the
    /// resolver refused them): a reference to one is not an undeclared-entity
    /// error, the processor simply did not read it.
    var unresolvedParameterEntities: Set<String> = []
    /// The URI of the entity whose text is being scanned (nil for the
    /// document): relative identifiers declared here resolve against it.
    var currentBase: String?
    /// Each external parameter entity's own resolved URI, the base for the
    /// identifiers its replacement declares.
    var parameterEntityBases: [String: String] = [:]
    var parameterBudget: Int
    /// Bounds parameter-entity injection recursion (modularized DTDs nest, but
    /// only a little); deeper references are ignored rather than trapping.
    let maxDepth = 40

    init(
        limits: PureXML.Parsing.Limits,
        resolver: PureXML.Parsing.EntityResolver,
        standalone: Bool = false,
        documentVersion: String? = nil,
    ) {
        self.limits = limits
        self.resolver = resolver
        self.standalone = standalone
        self.documentVersion = documentVersion ?? "1.0"
        parameterBudget = limits.maxEntityExpansion
    }

    /// Entity Declared is a WFC (throw) when the document is standalone, or
    /// has neither an external subset nor parameter entities; otherwise it is
    /// a VC (deferred finding), since the unread external declarations might
    /// have declared the entity (production 68).
    var entityDeclaredIsWellFormedness: Bool {
        if standalone { return true }
        return doctype.externalSubset == nil && doctype.parameterEntities.isEmpty && unresolvedParameterEntities.isEmpty
    }

    mutating func scan(_ reader: inout Reader, at mark: Mark) throws -> PureXML.Parsing.DocumentType {
        reader.consume("<!DOCTYPE")
        reader.skipSpace()
        doctype.name = scanName(&reader)
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
        try checkEntityRecursion(at: mark)
        return doctype
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
        inExternalContext = true
        currentBase = id.resolvedSystemID
        defer {
            inExternalContext = false
            currentBase = nil
        }
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
            // The reserved target 'xml' may not appear as a PI in the subset,
            // and the target must be separated from its data (production 16).
            let mark = reader.mark
            reader.consume("<?")
            let target = scanName(&reader)
            if target.lowercased() == "xml" {
                throw ParseError.reservedProcessingInstructionTarget(mark)
            }
            if target.contains(":") {
                throw ParseError.namespaceConstraint(reason: "PI target '\(target)' is not a legal NCName", mark)
            }
            if let next = reader.peek(), !next.isWhitespace, !reader.matches("?>") {
                throw ParseError.unexpectedCharacter(next, reader.mark)
            }
            skip(&reader, until: "?>")
        } else {
            // Any other construct here (an unknown or lowercase declaration
            // keyword, space after '<!', a DOCTYPE inside a subset, a bare '<')
            // is not well-formed.
            throw ParseError.malformedDeclaration(reader.mark)
        }
    }

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
            if !inExternalContext {
                doctype.internalEntities.insert(name)
            }
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
        let raw = recoveringDeclarationBody(readUntilClose(&reader), kind: "<!ELEMENT>", name: name)
        try checkStrictSubsetReferences(raw, at: mark)
        checkGroupNesting(raw, element: name)
        let model = expandParameterReferences(raw).trimmingXMLWhitespace()
        guard PureXML.Parsing.DTDContentModelGrammar.isValid(model) else {
            throw PureXML.Parsing.ParseError.invalidContentModel(element: name, mark)
        }
        guard !name.isEmpty else { return }
        guard doctype.elementModels[name] == nil else {
            doctype.duplicateElements.insert(name)
            return
        }
        doctype.elementModels[name] = model
        if !inExternalContext {
            doctype.internalElementModels.insert(name)
        }
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
        let rawBody = recoveringDeclarationBody(readUntilClose(&reader), kind: "<!ATTLIST>", name: name)
        try checkStrictSubsetReferences(rawBody, skippingQuoted: true, at: mark)
        let body = expandParameterReferences(rawBody)
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
        if !inExternalContext {
            if let existing = doctype.internalAttributeLists[name] {
                doctype.internalAttributeLists[name] = "\(existing) \(trimmed)"
            } else {
                doctype.internalAttributeLists[name] = trimmed
            }
        }
    }
}

extension DTDScanner {
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

    /// Reads to the declaration's closing `>`. `closed` is false when the
    /// input ended first, which can still be legal if a parameter-entity
    /// replacement supplies the `>` (VC: Proper Declaration/PE Nesting).
    private func readUntilClose(_ reader: inout Reader) -> (text: String, closed: Bool) {
        var text = ""
        while let character = reader.peek(), character != ">" {
            text.append(character)
            reader.advance()
        }
        return (text, reader.consume(">"))
    }

    /// When a declaration's `>` came from a parameter-entity replacement (the
    /// source ended first), records the VC: Proper Declaration/PE Nesting
    /// finding and truncates the expanded body at that `>`.
    mutating func recoveringDeclarationBody(_ read: (text: String, closed: Bool), kind: String, name: String) -> String {
        guard !read.closed else { return read.text }
        let expanded = expandParameterReferences(read.text)
        guard let close = expanded.firstIndex(of: ">") else { return read.text }
        doctype.validityFindings.append(PureXML.Parsing.ValidityFinding(
            "the \(kind) declaration for '\(name)' is completed inside a parameter-entity replacement (VC: Proper Declaration/PE Nesting)",
            subject: name,
        ))
        return String(expanded[..<close])
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
