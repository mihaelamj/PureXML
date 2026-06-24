/// Content markup dispatch, in its own file to keep the reader's primary type
/// body under the length cap. Behavior is part of EventReader proper.
extension PureXML.Parsing.EventReader {
    /// At a '<' in element content, dispatches to the matching markup scanner.
    /// The caller has confirmed the lead is '<' and set the event start. Shared
    /// by the byte and Character dispatch paths so the two cannot diverge.
    ///
    /// On the byte fast path the single byte after '<' selects the branch ('/'
    /// end tag, '?' PI, '!' a declaration, otherwise a start tag), so an
    /// element no longer runs up to five literal string comparisons before the
    /// start-tag branch wins. The Character path below is the exact fallback for
    /// a streaming source or spliced entity text, and a '<!' that matches none
    /// of comment/CDATA/DOCTYPE still falls through to the start-tag scanner,
    /// which reports the same `expectedName` error as before.
    mutating func scanContentMarkup() throws -> Event {
        switch reader.peekByte(1) {
        case 0x2F: // '/'
            try scanEndTag()
        case 0x3F: // '?'
            try scanContentProcessingInstruction()
        case 0x21: // '!'
            try scanContentDeclaration()
        case .some:
            try scanStartTag()
        case nil:
            try scanContentMarkupViaCharacters()
        }
    }

    /// The Character-path markup dispatch, used off the byte fast path (a
    /// streaming source or spliced entity text). Equivalent to the byte switch
    /// in `scanContentMarkup`.
    private mutating func scanContentMarkupViaCharacters() throws -> Event {
        if reader.matches("</") { return try scanEndTag() }
        if reader.matches("<?") { return try scanContentProcessingInstruction() }
        if reader.matches("<!") { return try scanContentDeclaration() }
        return try scanStartTag()
    }

    /// Scans a `<!...` construct in element content: a comment, a CDATA
    /// section, or a rejected DOCTYPE. A `<!` matching none of these falls
    /// through to the start-tag scanner, which reports the same `expectedName`
    /// error as before.
    private mutating func scanContentDeclaration() throws -> Event {
        if reader.matches("<!--") {
            recordEmptyElementContent("a comment")
            return try scanComment()
        }
        if reader.matches("<![CDATA[") { return try scanCDATA() }
        if reader.matches("<!DOCTYPE") {
            throw PureXML.Parsing.ParseError.unsupportedDoctype(reader.mark)
        }
        return try scanStartTag()
    }

    /// Scans a processing instruction in element content, rejecting the
    /// reserved `xml` target (legal only as the document's leading declaration).
    private mutating func scanContentProcessingInstruction() throws -> Event {
        let mark = reader.mark
        recordEmptyElementContent("a processing instruction")
        let instruction = try scanProcessingInstruction()
        if instruction.target.lowercased() == "xml" {
            throw PureXML.Parsing.ParseError.reservedProcessingInstructionTarget(mark)
        }
        return .processingInstruction(target: instruction.target, data: instruction.data)
    }
}
