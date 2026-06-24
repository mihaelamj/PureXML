/// One step of the explicit serialization walk: either a node to write, or a
/// pending close tag to emit once a node's children are done. File-scope and
/// private: an internal detail of the iterative serializer.
private enum SerializeStep {
    case node(PureXML.Model.Node, Int, Bool)
    case close(SerializeClose)
}

/// The deferred close tag for an element, carried on the work stack.
private struct SerializeClose {
    let name: String
    let depth: Int
    let formatted: Bool
    let indentClose: Bool
}

public extension PureXML.Emitting {
    /// Serializes a ``PureXML/Model/Node`` tree back into XML text.
    ///
    /// The walk is iterative, not recursive: it drives an explicit work stack so
    /// that arbitrarily deep documents cannot overflow the call stack (the
    /// approach libxml2 takes in `xmlNodeDumpOutputInternal`). Reimplemented in
    /// Swift; no upstream code is copied.
    struct Serializer: Sendable {
        public var options: Options

        public init(options: Options = .default) {
            self.options = options
        }

        /// Serializes a node into bytes in `encoding`, the libxml2
        /// `xmlSaveToFilename(..., encoding)` model. The XML declaration carries the
        /// encoding's canonical name, a byte-order mark precedes a UTF-16/32 stream,
        /// and any scalar the encoding cannot represent becomes a numeric character
        /// reference. Falls back to UTF-8 for an encoding without an output table.
        public func serialize(_ node: PureXML.Model.Node, encoding: PureXML.Parsing.InputEncoding) -> [UInt8] {
            var encodingOptions = options
            encodingOptions.includeXMLDeclaration = true
            encodingOptions.encodingName = PureXML.Parsing.ByteEncoder.canonicalName(encoding)
            let text = Serializer(options: encodingOptions).serialize(node)
            return PureXML.Parsing.ByteEncoder.byteOrderMark(encoding)
                + PureXML.Parsing.ByteEncoder.encode(text, as: encoding)
        }

        /// Serializes a node into an XML string.
        public func serialize(_ node: PureXML.Model.Node) -> String {
            var output = ""
            if let declaration = options.xmlDeclaration {
                output += declaration + options.lineEnding
            }
            var stack: [SerializeStep] = [.node(node, 0, options.prettyPrint)]
            while let step = stack.popLast() {
                switch step {
                case let .node(node, depth, formatted):
                    write(node, depth: depth, formatted: formatted, output: &output, stack: &stack)
                case let .close(close):
                    if close.indentClose {
                        output += pad(close.depth)
                    }
                    output += "</\(close.name)>"
                    if close.formatted {
                        output += options.lineEnding
                    }
                }
            }
            return output
        }

        private func write(
            _ node: PureXML.Model.Node,
            depth: Int,
            formatted: Bool,
            output: inout String,
            stack: inout [SerializeStep],
        ) {
            switch node {
            case let .document(children):
                push(children, depth: depth, formatted: formatted, into: &stack)
            case let .element(element):
                write(element, depth: depth, formatted: formatted, output: &output, stack: &stack)
            case let .text(value):
                output += Escaping.text(value, asciiOnly: options.asciiOnly, escapeCarriageReturn: options.textEscaping.escapesCarriageReturn)
            case let .cdata(value):
                output += options.cdataAsText
                    ? Escaping.text(value, asciiOnly: options.asciiOnly, escapeCarriageReturn: options.textEscaping.escapesCarriageReturn)
                    : "<![CDATA[\(value)]]>"
            case let .comment(value):
                output += "<!--\(Escaping.comment(value))-->"
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(Escaping.processingInstruction(data))?>"
            }
        }

        private func write(
            _ element: PureXML.Model.Element,
            depth: Int,
            formatted: Bool,
            output: inout String,
            stack: inout [SerializeStep],
        ) {
            if formatted {
                output += pad(depth)
            }
            output += "<" + element.name.description
            let quote = options.attributeQuote.character
            for attribute in element.attributes {
                let value = Escaping.attribute(attribute.value, quote: quote, asciiOnly: options.asciiOnly)
                output += " \(attribute.name.description)=\(quote)\(value)\(quote)"
            }

            if element.children.isEmpty, options.selfCloseEmptyElements {
                output += "/>"
                if formatted {
                    output += options.lineEnding
                }
                return
            }

            output += ">"
            // Suppress formatting when the element has text or CDATA children:
            // re-indenting mixed content would change its significant whitespace.
            // libxml2 makes the same choice in xmlNodeDumpOutputInternal.
            let hasInlineContent = element.children.contains { child in
                switch child {
                case .text, .cdata: true
                default: false
                }
            }
            let childFormatted = childFormatting(of: element, parentFormatted: formatted, hasInlineContent: hasInlineContent)
            if childFormatted {
                output += options.lineEnding
            }
            stack.append(.close(SerializeClose(
                name: element.name.description,
                depth: depth,
                formatted: formatted,
                indentClose: childFormatted,
            )))
            push(
                element.children,
                depth: childFormatted ? depth + 1 : depth,
                formatted: childFormatted,
                into: &stack,
            )
        }

        /// Whether to format (indent) an element's children: never when it has
        /// inline content or none, never under `xml:space="preserve"` (its content
        /// is emitted verbatim), and otherwise as the parent decided, with
        /// `xml:space="default"` re-enabling formatting if the options pretty-print.
        private func childFormatting(of element: PureXML.Model.Element, parentFormatted: Bool, hasInlineContent: Bool) -> Bool {
            guard !hasInlineContent, !element.children.isEmpty else { return false }
            switch Self.xmlSpace(of: element) {
            case "preserve": return false
            case "default": return options.prettyPrint
            default: return parentFormatted
            }
        }

        private static func xmlSpace(of element: PureXML.Model.Element) -> String? {
            element.attributes.first { $0.name.localName == "space" && $0.name.prefix == "xml" }?.value
        }

        /// Pushes children in reverse so they pop off the work stack in order.
        private func push(
            _ children: [PureXML.Model.Node],
            depth: Int,
            formatted: Bool,
            into stack: inout [SerializeStep],
        ) {
            for child in children.reversed() {
                stack.append(.node(child, depth, formatted))
            }
        }

        private func pad(_ depth: Int) -> String {
            String(repeating: options.indent, count: depth)
        }
    }
}
