public extension PureXML.Parsing {
    /// A SAX-style set of callbacks, delivered as a document is parsed rather than
    /// building a tree (the libxml2 SAX2 model). Each callback is optional; set
    /// only the ones you need. Names are namespace-resolved ``Model/QualifiedName``
    /// values, so the URI is available on the callback.
    struct SAXHandler {
        public var startDocument: (() -> Void)?
        public var endDocument: (() -> Void)?
        public var startElement: ((PureXML.Model.QualifiedName, [PureXML.Model.Attribute]) -> Void)?
        public var endElement: ((PureXML.Model.QualifiedName) -> Void)?
        public var characters: ((String) -> Void)?
        public var cdata: ((String) -> Void)?
        public var comment: ((String) -> Void)?
        public var processingInstruction: ((_ target: String, _ data: String) -> Void)?

        public init(
            startDocument: (() -> Void)? = nil,
            endDocument: (() -> Void)? = nil,
            startElement: ((PureXML.Model.QualifiedName, [PureXML.Model.Attribute]) -> Void)? = nil,
            endElement: ((PureXML.Model.QualifiedName) -> Void)? = nil,
            characters: ((String) -> Void)? = nil,
            cdata: ((String) -> Void)? = nil,
            comment: ((String) -> Void)? = nil,
            processingInstruction: ((_ target: String, _ data: String) -> Void)? = nil,
        ) {
            self.startDocument = startDocument
            self.endDocument = endDocument
            self.startElement = startElement
            self.endElement = endElement
            self.characters = characters
            self.cdata = cdata
            self.comment = comment
            self.processingInstruction = processingInstruction
        }
    }
}
