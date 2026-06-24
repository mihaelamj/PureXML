/// Content markup dispatch, in its own file to keep the reader's primary type
/// body under the length cap. Behavior is part of EventReader proper.
extension PureXML.Parsing.EventReader {
    /// At a '<' in element content, dispatches to the matching markup scanner.
    /// The caller has confirmed the lead is '<' and set the event start. Shared
    /// by the byte and Character dispatch paths so the two cannot diverge.
    mutating func scanContentMarkup() throws -> Event {
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
                throw PureXML.Parsing.ParseError.reservedProcessingInstructionTarget(mark)
            }
            return .processingInstruction(target: instruction.target, data: instruction.data)
        }
        if reader.matches("<!DOCTYPE") {
            throw PureXML.Parsing.ParseError.unsupportedDoctype(reader.mark)
        }
        return try scanStartTag()
    }
}
