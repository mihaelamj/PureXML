/// The end-tag scanner, split from the reader body to keep it under the
/// length caps. Behavior is part of EventReader proper.
extension PureXML.Parsing.EventReader {
    /// Public: this alias shadows the public Parsing.Event for the whole
    /// type, so it must not narrow the public next() signature (#142).
    public typealias Event = PureXML.Parsing.Event
    typealias ParseError = PureXML.Parsing.ParseError
    mutating func scanEndTag() throws -> Event {
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
}
