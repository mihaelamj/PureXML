public extension PureXML.Parsing {
    /// A push-style XML parser: feed input as it arrives with ``feed(_:)`` and end
    /// the document with ``finish()``. It drives a ``SAXHandler``, holding only a
    /// small buffer (the current incomplete token) plus the open-element stack, so
    /// it never requires the whole document and resumes cleanly across chunk
    /// boundaries (the Expat `XML_TOK_PARTIAL` model).
    struct PushParser {
        private var buffer: [Character] = []
        private var namespaces = NamespaceContext()
        private var open: [PureXML.Model.QualifiedName] = []
        private let handler: SAXHandler
        private var started = false

        /// Creates a push parser delivering events to `sax`.
        public init(sax: SAXHandler) {
            handler = sax
        }

        /// Feeds the next chunk of input, delivering events for every token that is
        /// now complete.
        public mutating func feed(_ text: String) throws {
            buffer += Array(text)
            try drain(final: false)
        }

        /// Ends the document, flushing any trailing token and the document-end
        /// callback.
        public mutating func finish() throws {
            ensureStarted()
            try drain(final: true)
            handler.endDocument?()
        }

        private mutating func ensureStarted() {
            guard !started else { return }
            started = true
            handler.startDocument?()
        }

        private mutating func drain(final: Bool) throws {
            ensureStarted()
            while case let .token(token, consumed) = PushScanner.scan(buffer, final: final) {
                buffer.removeFirst(consumed)
                try deliver(token)
            }
        }

        private mutating func deliver(_ token: PushToken) throws {
            switch token {
            case let .open(name, attributes, selfClosing):
                try open(name, attributes, selfClosing: selfClosing)
            case let .close(name):
                close(name)
            case let .text(value):
                if !value.isEmpty { handler.characters?(value) }
            case let .comment(value):
                handler.comment?(value)
            case let .cdata(value):
                handler.cdata?(value)
            case let .processingInstruction(target, data):
                if target.lowercased() != "xml" { handler.processingInstruction?(target, data) }
            case .ignorable:
                break
            }
        }

        private mutating func open(_ name: String, _ attributes: [PushAttribute], selfClosing: Bool) throws {
            let rawName = PureXML.Model.QualifiedName(name)
            let rawAttributes = attributes.map { PureXML.Model.Attribute(name: .init($0.name), value: $0.value) }
            let resolved = try namespaces.enterElement(name: rawName, attributes: rawAttributes, at: .start)
            handler.startElement?(resolved.name, resolved.attributes)
            if selfClosing {
                namespaces.leaveElement()
                handler.endElement?(resolved.name)
            } else {
                open.append(resolved.name)
            }
        }

        private mutating func close(_: String) {
            guard let top = open.popLast() else { return }
            namespaces.leaveElement()
            handler.endElement?(top)
        }
    }
}
