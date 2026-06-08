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
        /// An attribute the cursor was moved onto with ``TextReader/moveToFirstAttribute()``
        /// and friends. Never produced by ``TextReader/read()``.
        case attribute
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
        private var lookaheadStart: Mark = .start
        private var finished = false
        private var currentDepth = 0
        /// The qualified name of the current element or attribute node, for the
        /// namespace accessors; nil on a node that has no name.
        private var currentName: PureXML.Model.QualifiedName?
        /// The element the cursor last read, so ``moveToElement()`` can return to it.
        private var elementName: PureXML.Model.QualifiedName?
        /// The reported depth of that element, restored by ``moveToElement()``.
        private var elementDepth = 0
        /// The attribute index the cursor was moved onto, or nil when on the element.
        private var attributeCursor: Int?
        /// The in-scope `xml:lang` for each open element, innermost last.
        private var langStack: [String?] = []
        private var position: Mark = .start

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
        /// The in-scope `xml:lang` of the current node, inherited from ancestors
        /// unless the current element overrides it; nil when none is declared.
        public private(set) var xmlLang: String?

        /// The resolved namespace URI of the current element or attribute, or nil
        /// when it is in no namespace or the node has no name.
        public var namespaceURI: String? {
            currentName?.namespaceURI
        }

        /// The local part of the current element's or attribute's name.
        public var localName: String {
            currentName?.localName ?? name
        }

        /// The namespace prefix of the current element or attribute, if any.
        public var prefix: String? {
            currentName?.prefix
        }

        /// The one-based line where the current node begins.
        public var lineNumber: Int {
            position.line
        }

        /// The one-based column where the current node begins.
        public var columnNumber: Int {
            position.column
        }

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

        /// Moves the cursor onto the current element's first attribute, exposing it
        /// as an ``ReaderNodeKind/attribute`` node. Returns false when the element
        /// has no attributes. ``moveToElement()`` returns to the element.
        @discardableResult
        public mutating func moveToFirstAttribute() -> Bool {
            guard !attributes.isEmpty else { return false }
            showAttribute(0)
            return true
        }

        /// Moves the cursor onto the next attribute, returning false past the last.
        @discardableResult
        public mutating func moveToNextAttribute() -> Bool {
            let next = (attributeCursor ?? -1) + 1
            guard next < attributes.count else { return false }
            showAttribute(next)
            return true
        }

        /// Moves the cursor onto the named attribute, returning false when absent.
        @discardableResult
        public mutating func moveToAttribute(_ name: String) -> Bool {
            guard let index = attributes.firstIndex(where: { $0.name.description == name }) else { return false }
            showAttribute(index)
            return true
        }

        /// Returns the cursor from an attribute node back to its element. Returns
        /// false when the cursor is not on an attribute.
        @discardableResult
        public mutating func moveToElement() -> Bool {
            guard attributeCursor != nil, let elementName else { return false }
            attributeCursor = nil
            currentName = elementName
            set(.element, name: elementName.description, depth: elementDepth)
            return true
        }

        private mutating func showAttribute(_ index: Int) {
            attributeCursor = index
            let attribute = attributes[index]
            currentName = attribute.name
            set(.attribute, name: attribute.name.description, value: attribute.value, depth: elementDepth + 1)
        }

        /// Advances to the next node. Returns false at the end of the document.
        public mutating func read() throws -> Bool {
            attributeCursor = nil
            guard let (event, start) = try nextEvent() else {
                resetToEnd()
                return false
            }
            position = start
            apply(event)
            return true
        }

        private mutating func apply(_ event: Event) {
            isEmptyElement = false
            attributes = []
            value = ""
            currentName = nil
            xmlLang = langStack.last ?? nil
            switch event {
            case let .startElement(name, attributes):
                applyStartElement(name: name, attributes: attributes)
            case let .endElement(name):
                currentDepth -= 1
                if !langStack.isEmpty { langStack.removeLast() }
                currentName = name
                xmlLang = langStack.last ?? nil
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
            currentName = name
            elementName = name
            elementDepth = currentDepth
            xmlLang = Self.xmlLang(of: attributes) ?? (langStack.last ?? nil)
            if consumeMatchingEnd(of: name) {
                isEmptyElement = true
                set(.element, name: name.description, depth: currentDepth)
            } else {
                langStack.append(xmlLang)
                set(.element, name: name.description, depth: currentDepth)
                currentDepth += 1
            }
        }

        /// The value of an `xml:lang` attribute in `attributes`, if present.
        private static func xmlLang(of attributes: [PureXML.Model.Attribute]) -> String? {
            attributes.first { $0.name.localName == "lang" && $0.name.prefix == "xml" }?.value
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
            currentName = nil
            attributeCursor = nil
            xmlLang = nil
        }

        private mutating func peekEvent() -> Event? {
            if lookahead == nil, !finished {
                lookahead = try? events.next()
                lookaheadStart = events.eventStart
            }
            return lookahead
        }

        private mutating func nextEvent() throws -> (event: Event, start: Mark)? {
            if let buffered = lookahead {
                lookahead = nil
                return (buffered, lookaheadStart)
            }
            guard let event = try events.next() else { return nil }
            return (event, events.eventStart)
        }
    }
}
