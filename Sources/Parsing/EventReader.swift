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
        private var reader: Reader
        private let limits: Limits
        private let resolver: EntityResolver
        private var open: [PureXML.Model.QualifiedName] = []
        private var namespaces = NamespaceContext()
        /// The DTD information extracted so far (entities, element models,
        /// attribute lists, parameter entities, and external identifiers).
        private(set) var documentType = DocumentType()
        private var entityBudget: Int

        private var pending: [Event] = []
        private var sawRoot = false
        private var primed = false
        /// When true, ``next()`` repairs malformed input in place instead of
        /// throwing: it records a ``Diagnostic`` and emits best-effort events.
        private let recovering: Bool
        private var reachedEnd = false
        /// The problems found so far, when reading in recovering mode.
        private(set) var diagnostics: [Diagnostic] = []

        /// Creates a reader over a character-pulling source. The closure returns
        /// the next character or nil at end of input.
        init(
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
        init(_ string: String, limits: Limits = .default, resolver: EntityResolver = .refusing, recovering: Bool = false) {
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
        mutating func next() throws -> Event? {
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
                if reader.matches("<!--") {
                    return try scanComment()
                }
                if reader.matches("<?") {
                    let instruction = try scanProcessingInstruction()
                    if instruction.target.lowercased() == "xml" { continue }
                    return .processingInstruction(target: instruction.target, data: instruction.data)
                }
                if reader.matches("<!DOCTYPE") {
                    documentType = try DoctypeScanner.scan(&reader, limits: limits, resolver: resolver)
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
            guard let lead = reader.peek() else {
                throw ParseError.unexpectedEndOfInput(reader.mark)
            }
            if reader.matches("</") { return try scanEndTag() }
            if reader.matches("<!--") { return try scanComment() }
            if reader.matches("<![CDATA[") { return try scanCDATA() }
            if reader.matches("<?") {
                let instruction = try scanProcessingInstruction()
                return .processingInstruction(target: instruction.target, data: instruction.data)
            }
            if reader.matches("<!DOCTYPE") {
                throw ParseError.unsupportedDoctype(reader.mark)
            }
            if lead == "<" { return try scanStartTag() }
            return try scanText()
        }

        private mutating func scanStartTag() throws -> Event {
            guard open.count < limits.maxDepth else {
                throw ParseError.nestingTooDeep(limit: limits.maxDepth, reader.mark)
            }
            let mark = reader.mark
            reader.consume("<")
            let rawName = try scanName()
            let rawAttributes = try scanAttributes()
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

        private mutating func scanEndTag() throws -> Event {
            let mark = reader.mark
            reader.consume("</")
            let name = try scanName()
            reader.skipSpace()
            guard reader.consume(">") else {
                throw ParseError.unterminatedTag(reader.mark)
            }
            guard let top = open.last else {
                throw ParseError.unexpectedEndTag(name: name.description, mark)
            }
            // Tag matching is lexical (the qualified-name text must match); the
            // open name additionally carries its resolved namespace URI.
            guard top.description == name.description else {
                throw ParseError.mismatchedEndTag(expected: top.description, found: name.description, mark)
            }
            open.removeLast()
            namespaces.leaveElement()
            return .endElement(name: top)
        }

        private mutating func scanText() throws -> Event {
            let mark = reader.mark
            var raw = ""
            var length = 0
            while let character = reader.peek(), character != "<" {
                length += 1
                try checkContent(length, mark)
                raw.append(character)
                reader.advance()
            }
            return try .characters(EntityDecoder.decode(raw, entities: documentType.entities, budget: &entityBudget, at: mark))
        }

        private mutating func scanProcessingInstruction() throws -> (target: String, data: String) {
            let mark = reader.mark
            reader.consume("<?")
            let target = try scanName()
            reader.skipSpace()
            var data = ""
            var length = 0
            while !reader.matches("?>") {
                guard let character = reader.advance() else {
                    throw ParseError.unterminatedTag(mark)
                }
                length += 1
                try checkContent(length, mark)
                data.append(character)
            }
            reader.consume("?>")
            return (target.description, data)
        }

        private mutating func scanAttributes() throws -> [PureXML.Model.Attribute] {
            var attributes: [PureXML.Model.Attribute] = []
            var seen: Set<String> = []
            while true {
                reader.skipSpace()
                guard let next = reader.peek(), next != ">", next != "/" else {
                    return attributes
                }
                let mark = reader.mark
                let name = try scanName()
                reader.skipSpace()
                guard reader.consume("=") else {
                    throw ParseError.expectedEquals(reader.mark)
                }
                reader.skipSpace()
                let value = try scanAttributeValue()
                guard seen.insert(name.description).inserted else {
                    if recovering {
                        // Keep the element: record the duplicate and drop the later
                        // occurrence rather than failing the whole start tag.
                        diagnostics.append(Diagnostic(.duplicateAttribute(name: name.description, mark)))
                        continue
                    }
                    throw ParseError.duplicateAttribute(name: name.description, mark)
                }
                attributes.append(PureXML.Model.Attribute(name: name, value: value))
            }
        }

        private mutating func scanAttributeValue() throws -> String {
            let mark = reader.mark
            guard let quote = reader.peek(), quote == "\"" || quote == "'" else {
                throw ParseError.unquotedAttributeValue(reader.mark)
            }
            reader.advance()
            var raw = ""
            var length = 0
            while let character = reader.peek(), character != quote {
                length += 1
                try checkContent(length, mark)
                raw.append(character)
                reader.advance()
            }
            guard reader.consume(String(quote)) else {
                throw ParseError.unexpectedEndOfInput(reader.mark)
            }
            return try EntityDecoder.decode(raw, entities: documentType.entities, budget: &entityBudget, at: mark)
        }

        private mutating func scanName() throws -> PureXML.Model.QualifiedName {
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

        private func checkContent(_ length: Int, _ mark: Mark) throws {
            guard length <= limits.maxContentLength else {
                throw ParseError.contentTooLong(limit: limits.maxContentLength, mark)
            }
        }
    }
}

extension PureXML.Parsing.EventReader {
    /// The current source offset, used to tell whether a failing ``next()`` made
    /// progress before throwing.
    var offset: Int {
        reader.mark.offset
    }

    /// Resynchronizes after a failed ``next()`` that started at `offset`, so
    /// reading can resume past a recorded diagnostic. Returns false at end of
    /// input. If the failed scan already advanced (it consumed the malformed
    /// construct), reading retries from the new position; if it threw without
    /// progress, the offending run is skipped up to the next markup start. Either
    /// way at least one character is consumed when input remains, so a recovering
    /// loop is guaranteed to terminate.
    mutating func recover(from offset: Int) -> Bool {
        pending.removeAll()
        guard reader.peek() != nil else { return false }
        if reader.mark.offset > offset { return true }
        reader.advance()
        while let character = reader.peek(), character != "<" {
            reader.advance()
        }
        return true
    }

    /// Pops the open-element stack down to (and including) the most recent element
    /// named `found`, synthesizing an end-tag event for each closed element,
    /// innermost first. Returns the first such event with the rest queued, so a
    /// mismatched end tag implicitly closes the elements nested inside the match.
    /// Returns nil when no open element matches, dropping the stray end tag.
    mutating func scanComment() throws -> PureXML.Parsing.Event {
        let mark = reader.mark
        reader.consume("<!--")
        var content = ""
        var length = 0
        while !reader.matches("-->") {
            guard let character = reader.advance() else {
                throw PureXML.Parsing.ParseError.unterminatedComment(mark)
            }
            length += 1
            try checkContent(length, mark)
            content.append(character)
        }
        reader.consume("-->")
        return .comment(content)
    }

    mutating func scanCDATA() throws -> PureXML.Parsing.Event {
        let mark = reader.mark
        reader.consume("<![CDATA[")
        var content = ""
        var length = 0
        while !reader.matches("]]>") {
            guard let character = reader.advance() else {
                throw PureXML.Parsing.ParseError.unterminatedCDATA(mark)
            }
            length += 1
            try checkContent(length, mark)
            content.append(character)
        }
        reader.consume("]]>")
        return .cdata(content)
    }

    /// Handles a thrown error in recovering mode: records the diagnostic and
    /// returns an event to emit (an end tag synthesized by popping to a match) or
    /// nil to continue after resynchronizing. Marks the end of input on truncation
    /// or an exhausted source.
    mutating func recoveredEvent(from error: PureXML.Parsing.ParseError, startingAt start: Int) -> PureXML.Parsing.Event? {
        diagnostics.append(PureXML.Parsing.Diagnostic(error))
        switch error {
        case .unexpectedEndOfInput:
            reachedEnd = true
            return nil
        case let .mismatchedEndTag(_, found, _), let .unexpectedEndTag(found, _):
            return closeTo(found)
        default:
            if !recover(from: start) { reachedEnd = true }
            return nil
        }
    }

    mutating func closeTo(_ found: String) -> PureXML.Parsing.Event? {
        guard let index = open.lastIndex(where: { $0.description == found }) else { return nil }
        var events: [PureXML.Parsing.Event] = []
        while open.count > index {
            let closed = open.removeLast()
            namespaces.leaveElement()
            events.append(.endElement(name: closed))
        }
        guard let first = events.first else { return nil }
        pending.append(contentsOf: events.dropFirst())
        return first
    }
}
