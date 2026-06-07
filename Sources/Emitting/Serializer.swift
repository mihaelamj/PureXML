public extension PureXML.Emitting {
    /// Serializes a ``PureXML/Model/Node`` tree back into XML text.
    ///
    /// Unlike the parser, the serializer is implemented: it is the working half
    /// of the round-trip and lets callers build trees programmatically and emit
    /// well-formed XML today.
    struct Serializer: Sendable {
        public var options: Options

        public init(options: Options = .default) {
            self.options = options
        }

        /// Serializes a node into an XML string.
        public func serialize(_ node: PureXML.Model.Node) -> String {
            var output = ""
            write(node, depth: 0, into: &output)
            return output
        }

        private func write(_ node: PureXML.Model.Node, depth: Int, into output: inout String) {
            switch node {
            case let .document(children):
                writeChildren(children, depth: depth, into: &output)
            case let .element(element):
                write(element, depth: depth, into: &output)
            case let .text(value):
                output += Self.escapeText(value)
            case let .cdata(value):
                output += "<![CDATA[\(value)]]>"
            case let .comment(value):
                output += "<!--\(value)-->"
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
            }
        }

        private func write(_ element: PureXML.Model.Element, depth: Int, into output: inout String) {
            let pad = options.prettyPrint ? String(repeating: options.indent, count: depth) : ""
            output += pad + "<" + element.name.description
            for attribute in element.attributes {
                output += " \(attribute.name.description)=\"\(Self.escapeAttribute(attribute.value))\""
            }

            if element.children.isEmpty, options.selfCloseEmptyElements {
                output += "/>"
                if options.prettyPrint { output += "\n" }
                return
            }

            output += ">"
            let onlyText = element.children.allSatisfy { if case .text = $0 { true } else { false } }
            if options.prettyPrint, !onlyText {
                output += "\n"
                writeChildren(element.children, depth: depth + 1, into: &output)
                output += pad
            } else {
                for child in element.children {
                    write(child, depth: 0, into: &output)
                }
            }
            output += "</\(element.name.description)>"
            if options.prettyPrint { output += "\n" }
        }

        private func writeChildren(_ children: [PureXML.Model.Node], depth: Int, into output: inout String) {
            for child in children {
                write(child, depth: depth, into: &output)
            }
        }

        private static func escapeText(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                default: result.append(character)
                }
            }
            return result
        }

        private static func escapeAttribute(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case "\"": result += "&quot;"
                default: result.append(character)
                }
            }
            return result
        }
    }
}
