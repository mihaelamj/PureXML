public extension PureXML.Parsing {
    /// A single XML parse event emitted by the streaming ``EventReader``.
    ///
    /// An empty element `<br/>` emits ``startElement(name:attributes:)`` followed
    /// immediately by ``endElement(name:)``, so consumers see a consistent
    /// open/close pair regardless of the source syntax.
    enum Event: Equatable, Sendable {
        case startElement(name: PureXML.Model.QualifiedName, attributes: [PureXML.Model.Attribute])
        case endElement(name: PureXML.Model.QualifiedName)
        case characters(String)
        case cdata(String)
        case comment(String)
        case processingInstruction(target: String, data: String)
    }
}
