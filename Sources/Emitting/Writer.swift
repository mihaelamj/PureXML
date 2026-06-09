/// What has been written inside an open element so far, used to decide
/// indentation and self-closing. File-scope and private.
private enum WriterContent {
    case empty
    case elements
    case text
}

public extension PureXML.Emitting {
    /// An incremental XML writer (the libxml2 `xmlTextWriter` model): emit a
    /// document by calling start/end and write methods, never building a tree.
    /// Escaping matches ``Serializer``. In compact mode the output is byte-identical
    /// to serializing the equivalent tree; in pretty mode element children are
    /// indented, but because the writer is forward-only it cannot retroactively
    /// suppress indentation when text appears later, so prefer compact for exact
    /// round-tripping of mixed content.
    ///
    /// Methods are forgiving: a `writeAttribute` after content, or an unbalanced
    /// `writeEndElement`, is ignored rather than trapping. Read ``output`` for the
    /// accumulated XML.
    struct Writer {
        public private(set) var output = ""
        private let options: Options
        private var open: [String] = []
        private var content: [WriterContent] = []
        private var startTagOpen = false

        public init(options: Options = .default) {
            self.options = options
        }

        /// Emits the XML declaration if the options request one. Call before the
        /// root element; a no-op when `includeXMLDeclaration` is off.
        public mutating func writeStartDocument() {
            if let declaration = options.xmlDeclaration {
                output += declaration + options.lineEnding
            }
        }

        /// Opens an element. Attributes may follow until any content or close.
        public mutating func writeStartElement(_ name: String) {
            closeStartTag()
            if options.prettyPrint, !open.isEmpty {
                output += options.lineEnding + pad(open.count)
            }
            output += "<\(name)"
            markParentHasElements()
            open.append(name)
            content.append(.empty)
            startTagOpen = true
        }

        /// Opens an element with a namespace-qualified name, optionally declaring
        /// the namespace on it. A nil `prefix` writes an unprefixed name and, with a
        /// URI, a default-namespace declaration.
        public mutating func writeStartElementNS(prefix: String?, localName: String, namespaceURI: String?) {
            let qualified = prefix.map { "\($0):\(localName)" } ?? localName
            writeStartElement(qualified)
            if let namespaceURI {
                writeNamespace(prefix: prefix, uri: namespaceURI)
            }
        }

        /// Declares a namespace on the currently open start tag: `xmlns:prefix`, or
        /// `xmlns` when `prefix` is nil, bound to `uri`.
        public mutating func writeNamespace(prefix: String?, uri: String) {
            writeAttribute(prefix.map { "xmlns:\($0)" } ?? "xmlns", uri)
        }

        /// Writes an attribute on the currently open start tag.
        public mutating func writeAttribute(_ name: String, _ value: String) {
            guard startTagOpen else { return }
            let quote = options.attributeQuote.character
            output += " \(name)=\(quote)\(Escaping.attribute(value, quote: quote, asciiOnly: options.asciiOnly))\(quote)"
        }

        /// Writes escaped character data into the current element.
        public mutating func writeString(_ text: String) {
            closeStartTag()
            output += Escaping.text(text, asciiOnly: options.asciiOnly, escapeCarriageReturn: options.textEscaping.escapesCarriageReturn)
            setTopContent(.text)
        }

        /// Writes a `<![CDATA[ ... ]]>` section, or its escaped text when
        /// `cdataAsText` is set.
        public mutating func writeCData(_ text: String) {
            closeStartTag()
            if options.cdataAsText {
                output += Escaping.text(text, asciiOnly: options.asciiOnly, escapeCarriageReturn: options.textEscaping.escapesCarriageReturn)
            } else {
                output += "<![CDATA[\(text)]]>"
            }
            setTopContent(.text)
        }

        /// Writes a comment.
        public mutating func writeComment(_ text: String) {
            closeStartTag()
            if options.prettyPrint, !open.isEmpty {
                output += options.lineEnding + pad(open.count)
            }
            output += "<!--\(text)-->"
            markParentHasElements()
        }

        /// Writes a processing instruction.
        public mutating func writeProcessingInstruction(target: String, data: String) {
            closeStartTag()
            if options.prettyPrint, !open.isEmpty {
                output += options.lineEnding + pad(open.count)
            }
            output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
            markParentHasElements()
        }

        /// Closes the most recently opened element.
        public mutating func writeEndElement() {
            guard let name = open.popLast() else { return }
            let line = content.removeLast()
            if startTagOpen {
                startTagOpen = false
                if options.selfCloseEmptyElements {
                    output += "/>"
                    return
                }
                output += "></\(name)>"
                return
            }
            if options.prettyPrint, line == .elements {
                output += options.lineEnding + pad(open.count)
            }
            output += "</\(name)>"
        }

        /// Convenience: a complete element with text content.
        public mutating func writeElement(_ name: String, text: String) {
            writeStartElement(name)
            writeString(text)
            writeEndElement()
        }

        private mutating func closeStartTag() {
            guard startTagOpen else { return }
            output += ">"
            startTagOpen = false
        }

        private mutating func markParentHasElements() {
            if let last = content.indices.last, content[last] == .empty {
                content[last] = .elements
            }
        }

        private mutating func setTopContent(_ value: WriterContent) {
            if !content.isEmpty {
                content[content.count - 1] = value
            }
        }

        private func pad(_ depth: Int) -> String {
            String(repeating: options.indent, count: depth)
        }
    }
}
