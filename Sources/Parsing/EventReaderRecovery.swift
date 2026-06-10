extension PureXML.Parsing.EventReader {
    /// Records the first XML declaration's pseudo-attributes, throwing when they
    /// are malformed. A later `<?xml?>` (already invalid) is left untouched.
    mutating func recordDeclaration(_ data: String, at mark: PureXML.Parsing.Mark) throws {
        guard xmlDeclaration == nil else { return }
        guard let declaration = PureXML.Parsing.XMLDeclaration.parse(data) else {
            throw PureXML.Parsing.ParseError.malformedDeclaration(mark)
        }
        xmlDeclaration = declaration
        if declaration.version == "1.1" { reader.xml11 = true }
    }

    /// The current source offset, used to tell whether a failing ``next()`` made
    /// progress before throwing.
    var offset: Int {
        reader.mark.offset
    }

    /// The current source position, for attaching spans to ranged tree nodes.
    var mark: PureXML.Parsing.Mark {
        reader.mark
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
            // XML 1.0: '--' may not appear inside a comment (this also rejects
            // the '--->' ending, since its first two hyphens hit this check).
            if character == "-", reader.peek() == "-" {
                throw PureXML.Parsing.ParseError.doubleHyphenInComment(mark)
            }
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw PureXML.Parsing.ParseError.invalidCharacter(reader.mark)
            }
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
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw PureXML.Parsing.ParseError.invalidCharacter(reader.mark)
            }
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
