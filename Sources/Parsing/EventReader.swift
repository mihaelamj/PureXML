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
        private var open: [PureXML.Model.QualifiedName] = []
        private var namespaces = NamespaceContext()
        private var pending: [Event] = []
        private var sawRoot = false
        private var primed = false

        /// Creates a reader over a character-pulling source. The closure returns
        /// the next character or nil at end of input.
        init(pulling pull: @escaping () -> Character?, limits: Limits = .default) {
            reader = Reader(pulling: pull)
            self.limits = limits
        }

        /// Creates a reader over a string (a convenience over the streaming init).
        init(_ string: String, limits: Limits = .default) {
            reader = Reader(string)
            self.limits = limits
        }

        /// Returns the next event, or nil at the end of the document.
        mutating func next() throws -> Event? {
            if !primed {
                primed = true
                if reader.peek() == "\u{FEFF}" {
                    reader.advance()
                }
            }
            if !pending.isEmpty {
                return pending.removeFirst()
            }
            return open.isEmpty ? try nextAtTopLevel() : try nextInContent()
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
                    throw ParseError.unsupportedDoctype(reader.mark)
                }
                if reader.matches("</") || reader.matches("<![CDATA[") {
                    throw ParseError.junkAfterDocumentElement(reader.mark)
                }
                if lead == "<" {
                    guard !sawRoot else { throw ParseError.junkAfterDocumentElement(reader.mark) }
                    return try scanStartTag()
                }
                throw ParseError.junkAfterDocumentElement(reader.mark)
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
            return try .characters(EntityDecoder.decode(raw, at: mark))
        }

        private mutating func scanComment() throws -> Event {
            let mark = reader.mark
            reader.consume("<!--")
            var content = ""
            var length = 0
            while !reader.matches("-->") {
                guard let character = reader.advance() else {
                    throw ParseError.unterminatedComment(mark)
                }
                length += 1
                try checkContent(length, mark)
                content.append(character)
            }
            reader.consume("-->")
            return .comment(content)
        }

        private mutating func scanCDATA() throws -> Event {
            let mark = reader.mark
            reader.consume("<![CDATA[")
            var content = ""
            var length = 0
            while !reader.matches("]]>") {
                guard let character = reader.advance() else {
                    throw ParseError.unterminatedCDATA(mark)
                }
                length += 1
                try checkContent(length, mark)
                content.append(character)
            }
            reader.consume("]]>")
            return .cdata(content)
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
            return try EntityDecoder.decode(raw, at: mark)
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
