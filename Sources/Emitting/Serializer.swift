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

        /// Serializes a node into an XML string.
        public func serialize(_ node: PureXML.Model.Node) -> String {
            var output = ""
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
                        output += "\n"
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
                output += Escaping.text(value)
            case let .cdata(value):
                output += "<![CDATA[\(value)]]>"
            case let .comment(value):
                output += "<!--\(value)-->"
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
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
            for attribute in element.attributes {
                output += " \(attribute.name.description)=\"\(Escaping.attribute(attribute.value))\""
            }

            if element.children.isEmpty, options.selfCloseEmptyElements {
                output += "/>"
                if formatted {
                    output += "\n"
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
            let childFormatted = formatted && !hasInlineContent && !element.children.isEmpty
            if childFormatted {
                output += "\n"
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
