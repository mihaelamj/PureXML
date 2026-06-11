public extension PureXML.Parsing {
    /// A pull-based, streaming XML event reader.
    ///
    /// It consumes its input incrementally through a character-source closure and
    /// emits one ``Event`` at a time from ``next()``, holding only bounded state:
    /// a stack of open element names and a small lookahead buffer. It never
    /// requires the whole document in memory, so it can drive arbitrarily large
    /// or chunked input (a file, a socket, a generator). The tree-building
    /// ``Parser`` is a thin adapter over this core.
    ///
    /// Safe by default: a `<!DOCTYPE ...>` declaration is rejected rather than
    /// processed, removing the DTD-based threat classes (XXE, entity-expansion
    /// DoS) at the door. Bounded ``Limits`` cap depth, name, and content size.
    struct EventReader {
        var reader: Reader
        private let limits: Limits
        private let resolver: EntityResolver
        var open: [PureXML.Model.QualifiedName] = []
        var namespaces = NamespaceContext()
        /// The DTD information extracted so far (entities, element models,
        /// attribute lists, parameter entities, and external identifiers).
        var documentType = DocumentType()
        /// The parsed XML declaration `<?xml ... ?>`, when the document opens with
        /// one; nil otherwise.
        var xmlDeclaration: XMLDeclaration?
        var entityBudget: Int

        var pending: [Event] = []
        private var sawRoot = false
        private var primed = false
        /// When true, ``next()`` repairs malformed input in place instead of
        /// throwing: it records a ``Diagnostic`` and emits best-effort events.
        let recovering: Bool
        var reachedEnd = false
        /// The problems found so far, when reading in recovering mode.
        var diagnostics: [Diagnostic] = []
        /// The source position where the most recently produced event's node began,
        /// so a pull cursor can report each node's line and column.
        private(set) var eventStart: Mark = .start

        /// Creates a reader over a character-pulling source. The closure returns
        /// the next character or nil at end of input.
        public init(
            pulling pull: @escaping () -> Character?,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
            recovering: Bool = false,
        ) {
            reader = Reader(pulling: pull)
            self.limits = limits
            self.resolver = resolver
            self.recovering = recovering
            entityBudget = limits.maxEntityExpansion
        }

        /// Creates a reader over a string (a convenience over the streaming init).
        public init(_ string: String, limits: Limits = .default, resolver: EntityResolver = .refusing, recovering: Bool = false) {
            reader = Reader(string)
            self.limits = limits
            self.resolver = resolver
            self.recovering = recovering
            entityBudget = limits.maxEntityExpansion
        }

        /// Returns the next event, or nil at the end of the document. In recovering
        /// mode it never throws: each malformed construct is recorded as a
        /// diagnostic and reading continues, popping to a matching open element on
        /// a mismatched end tag and stopping (so the caller closes what is open) on
        /// truncation.
        public mutating func next() throws -> Event? {
            if !primed {
                primed = true
                if reader.peek() == "\u{FEFF}" {
                    reader.advance()
                }
            }
            while true {
                if !pending.isEmpty {
                    return pending.removeFirst()
                }
                guard recovering else {
                    return open.isEmpty ? try nextAtTopLevel() : try nextInContent()
                }
                if reachedEnd { return nil }
                let start = offset
                do {
                    return open.isEmpty ? try nextAtTopLevel() : try nextInContent()
                } catch let error as ParseError {
                    if let event = recoveredEvent(from: error, startingAt: start) { return event }
                }
            }
        }

        private mutating func nextAtTopLevel() throws -> Event? {
            while true {
                reader.skipSpace()
                guard let lead = reader.peek() else {
                    return nil
                }
                eventStart = reader.mark
                if reader.matches("<!--") {
                    return try scanComment()
                }
                if reader.matches("<?") {
                    let mark = reader.mark
                    let instruction = try scanProcessingInstruction()
                    if instruction.target.lowercased() == "xml" {
                        // The reserved target is only legal as the XML declaration,
                        // which must be the very first bytes of the document.
                        guard mark == .start, instruction.target == "xml" else {
                            throw ParseError.reservedProcessingInstructionTarget(mark)
                        }
                        try recordDeclaration(instruction.data, at: mark)
                        continue
                    }
                    return .processingInstruction(target: instruction.target, data: instruction.data)
                }
                if reader.matches("<!DOCTYPE") {
                    documentType = try DoctypeScanner.scan(
                        &reader,
                        limits: limits,
                        resolver: resolver,
                        standalone: xmlDeclaration?.standalone == true,
                        documentVersion: xmlDeclaration?.version,
                    )
                    continue
                }
                if reader.matches("</") || reader.matches("<![CDATA[") {
                    throw ParseError.junkAfterDocumentElement(reader.mark)
                }
                if lead == "<" {
                    guard !sawRoot else { throw ParseError.junkAfterDocumentElement(reader.mark) }
                    return try scanStartTag()
                }
                // Junk after the root is "content after the root element"; the same
                // shape before any root is simply an unexpected character.
                throw sawRoot
                    ? ParseError.junkAfterDocumentElement(reader.mark)
                    : ParseError.unexpectedCharacter(lead, reader.mark)
            }
        }

        private mutating func nextInContent() throws -> Event? {
            // Loops because a text scan can end by splicing an entity's
            // replacement into the reader with no text before it: the next
            // construct is then read from the spliced replacement.
            while true {
                guard let lead = reader.peek() else {
                    throw ParseError.unexpectedEndOfInput(reader.mark)
                }
                eventStart = reader.mark
                if reader.matches("</") { return try scanEndTag() }
                if reader.matches("<!--") {
                    recordEmptyElementContent("a comment")
                    return try scanComment()
                }
                if reader.matches("<![CDATA[") { return try scanCDATA() }
                if reader.matches("<?") {
                    let mark = reader.mark
                    recordEmptyElementContent("a processing instruction")
                    let instruction = try scanProcessingInstruction()
                    if instruction.target.lowercased() == "xml" {
                        throw ParseError.reservedProcessingInstructionTarget(mark)
                    }
                    return .processingInstruction(target: instruction.target, data: instruction.data)
                }
                if reader.matches("<!DOCTYPE") {
                    throw ParseError.unsupportedDoctype(reader.mark)
                }
                if lead == "<" { return try scanStartTag() }
                if let text = try scanText() { return text }
            }
        }

        private mutating func scanStartTag() throws -> Event {
            guard open.count < limits.maxDepth else {
                throw ParseError.nestingTooDeep(limit: limits.maxDepth, reader.mark)
            }
            let mark = reader.mark
            reader.consume("<")
            let rawName = try scanName()
            let rawAttributes = try normalizedBindings(element: rawName, attributes: scanAttributes())
            let resolved = try namespaces.enterElement(name: rawName, attributes: rawAttributes, at: mark)
            if reader.consume("/>") {
                namespaces.leaveElement()
                pending.append(.endElement(name: resolved.name))
                sawRoot = true
                return .startElement(name: resolved.name, attributes: resolved.attributes)
            }
            guard reader.consume(">") else {
                // Balance the namespace scope entered above so a recovering reader
                // can drop this malformed start tag without leaking a scope.
                namespaces.leaveElement()
                throw ParseError.unterminatedTag(reader.mark)
            }
            open.append(resolved.name)
            sawRoot = true
            return .startElement(name: resolved.name, attributes: resolved.attributes)
        }

        /// Returns the next text event, or nil after splicing: a reference to
        /// an entity whose replacement (directly or transitively) contains
        /// markup is validated, budgeted, and pushed back into the reader so
        /// it is reparsed as content (4.4.2 Included), elements in replacement
        /// text become elements in the stream, not character data.
        private mutating func scanText() throws -> Event? {
            let mark = reader.mark
            var raw = ""
            var length = 0
            while true {
                // Bulk byte runs first: plain ASCII content (the bulk of any
                // document) skips the per-character machinery entirely; the
                // run never spans '<', CR, ']', or invalid bytes, so the
                // character path below keeps exact error marks.
                if let run = reader.contentRunBytes() {
                    length += run.utf8.count
                    try checkContent(length, mark)
                    raw += run
                    continue
                }
                guard let character = reader.peek(), character != "<" else { break }
                length += 1
                try checkContent(length, mark)
                if character == ">", raw.hasSuffix("]]") {
                    throw ParseError.cdataCloseInContent(reader.mark)
                }
                guard character.unicodeScalars.allSatisfy(XMLCharacter.isChar) else {
                    throw ParseError.invalidCharacter(reader.mark)
                }
                raw.append(character)
                reader.advance()
            }
            let split = raw.contains("&") ? EntityDecoder.splitAtMarkupEntity(raw, entities: referencableEntities) : nil
            if let split {
                let replacement = try EntityDecoder.includeForContent(
                    split.name,
                    entities: referencableEntities,
                    budget: &entityBudget,
                    at: mark,
                )
                reader.inject(replacement + split.remainder)
                let prefix = try decodeReferences(split.prefix, at: mark)
                return prefix.isEmpty ? nil : .characters(prefix)
            }
            let decoded = try decodeReferences(raw, at: mark)
            recordReferenceContentFindings(raw: raw, decoded: decoded)
            return .characters(decoded)
        }

        private mutating func scanProcessingInstruction() throws -> (target: String, data: String) {
            let mark = reader.mark
            reader.consume("<?")
            let target = try scanName()
            // A PI target is an NCName under namespaces (no colon).
            if target.description.contains(":") {
                throw ParseError.namespaceConstraint(reason: "PI target '\(target.description)' is not a legal NCName", mark)
            }
            // Production 16: the target and the data must be separated by
            // whitespace, so `<?target+++?>` is not well-formed.
            if let next = reader.peek(), !next.isWhitespace, !reader.matches("?>") {
                throw ParseError.unexpectedCharacter(next, reader.mark)
            }
            reader.skipSpace()
            var data = ""
            var length = 0
            while !reader.matches("?>") {
                guard let character = reader.advance() else {
                    throw ParseError.unterminatedTag(mark)
                }
                length += 1
                try checkContent(length, mark)
                guard character.unicodeScalars.allSatisfy(XMLCharacter.isChar) else {
                    throw ParseError.invalidCharacter(reader.mark)
                }
                data.append(character)
            }
            reader.consume("?>")
            return (target.description, data)
        }

        mutating func scanName() throws -> PureXML.Model.QualifiedName {
            let mark = reader.mark
            guard let first = reader.peek(), first.isXMLNameStart else {
                throw ParseError.expectedName(reader.mark)
            }
            var raw = ""
            var length = 0
            while let character = reader.peek(), character.isXMLNameContinuation {
                length += 1
                guard length <= limits.maxNameLength else {
                    throw ParseError.nameTooLong(limit: limits.maxNameLength, mark)
                }
                raw.append(character)
                reader.advance()
            }
            return PureXML.Model.QualifiedName(raw)
        }

        func checkContent(_ length: Int, _ mark: Mark) throws {
            guard length <= limits.maxContentLength else {
                throw ParseError.contentTooLong(limit: limits.maxContentLength, mark)
            }
        }
    }
}
