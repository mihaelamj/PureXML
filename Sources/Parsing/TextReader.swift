public extension PureXML.Parsing {
    /// The kind of node a ``TextReader`` is positioned on (the libxml2
    /// `xmlReaderTypes` subset PureXML surfaces).
    enum ReaderNodeKind: Equatable, Sendable {
        /// Before the first ``TextReader/read()`` or after the end of input.
        case none
        case element
        case endElement
        case text
        case cdata
        case comment
        case processingInstruction
    }

    /// A pull cursor over an XML document (the libxml2 `xmlTextReader` model).
    ///
    /// Call ``read()`` to advance one node at a time; it returns false at the end
    /// of the document. After each successful read the cursor exposes the current
    /// node's ``nodeKind``, ``name``, ``value``, ``depth``, and ``attributes``.
    /// It is a thin, allocation-light layer over the streaming ``EventReader``: it
    /// never holds the whole document, so it drives arbitrarily large input.
    ///
    /// A childless element is reported once with ``isEmptyElement`` true and no
    /// separate end node, whether it was written `<a/>` or `<a></a>`; the
    /// streaming core normalizes the two forms.
    struct TextReader {
        private var events: EventReader
        private var lookahead: Event?
        private var finished = false
        private var currentDepth = 0

        /// The kind of the current node, or ``ReaderNodeKind/none`` before the
        /// first read and after the end.
        public private(set) var nodeKind: ReaderNodeKind = .none
        /// The current node's name: the element name or PI target, or the markers
        /// `#text`, `#cdata-section`, and `#comment`. Empty when on no node.
        public private(set) var name = ""
        /// The current node's character value: text/CDATA/comment content or PI
        /// data. Empty for element and end-element nodes.
        public private(set) var value = ""
        /// The current node's depth, counting from zero at the document element.
        public private(set) var depth = 0
        /// The current element's attributes; empty for non-element nodes.
        public private(set) var attributes: [PureXML.Model.Attribute] = []
        /// Whether the current node is a childless element reported as a single
        /// node (no matching end node follows).
        public private(set) var isEmptyElement = false

        public init(
            _ string: String,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) {
            events = EventReader(string, limits: limits, resolver: resolver)
        }

        /// The number of attributes on the current node.
        public var attributeCount: Int {
            attributes.count
        }

        /// The DTD read from the document's `<!DOCTYPE>` so far (entities, element
        /// models, attribute lists). The validation hook for a streaming cursor:
        /// pass it to ``PureXML/Validation/DTDSchema`` to check nodes as you read,
        /// or validate the assembled tree afterward. Empty unless DTD processing
        /// is enabled with `Limits(allowDoctype: true)`.
        public var documentType: DocumentType {
            events.documentType
        }

        /// Returns the value of the named attribute on the current element, or nil.
        public func attribute(_ name: String) -> String? {
            attributes.first { $0.name.description == name }?.value
        }

        /// Advances to the next node. Returns false at the end of the document.
        public mutating func read() throws -> Bool {
            guard let event = try nextEvent() else {
                resetToEnd()
                return false
            }
            apply(event)
            return true
        }

        private mutating func apply(_ event: Event) {
            isEmptyElement = false
            attributes = []
            value = ""
            switch event {
            case let .startElement(name, attributes):
                applyStartElement(name: name, attributes: attributes)
            case let .endElement(name):
                currentDepth -= 1
                set(.endElement, name: name.description, depth: currentDepth)
            case let .characters(text):
                set(.text, name: "#text", value: text)
            case let .cdata(text):
                set(.cdata, name: "#cdata-section", value: text)
            case let .comment(text):
                set(.comment, name: "#comment", value: text)
            case let .processingInstruction(target, data):
                set(.processingInstruction, name: target, value: data)
            }
        }

        private mutating func applyStartElement(
            name: PureXML.Model.QualifiedName,
            attributes: [PureXML.Model.Attribute],
        ) {
            self.attributes = attributes
            if consumeMatchingEnd(of: name) {
                isEmptyElement = true
                set(.element, name: name.description, depth: currentDepth)
            } else {
                set(.element, name: name.description, depth: currentDepth)
                currentDepth += 1
            }
        }

        /// Consumes a buffered end-element event that immediately closes `name`,
        /// marking the start as an empty element.
        private mutating func consumeMatchingEnd(of name: PureXML.Model.QualifiedName) -> Bool {
            guard case let .endElement(endName)? = peekEvent(), endName == name else { return false }
            lookahead = nil
            return true
        }

        private mutating func set(_ kind: ReaderNodeKind, name: String, value: String = "", depth: Int? = nil) {
            nodeKind = kind
            self.name = name
            self.value = value
            self.depth = depth ?? currentDepth
        }

        private mutating func resetToEnd() {
            finished = true
            nodeKind = .none
            name = ""
            value = ""
            attributes = []
            isEmptyElement = false
        }

        private mutating func peekEvent() -> Event? {
            if lookahead == nil, !finished {
                lookahead = try? events.next()
            }
            return lookahead
        }

        private mutating func nextEvent() throws -> Event? {
            if let buffered = lookahead {
                lookahead = nil
                return buffered
            }
            return try events.next()
        }
    }
}
