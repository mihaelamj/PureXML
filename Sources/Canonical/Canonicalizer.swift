public extension PureXML.Canonical {
    /// Produces the Canonical XML (C14N) form of a node (the libxml2 `c14n.h`
    /// model): UTF-8 text with namespace declarations and attributes in canonical
    /// order, empty elements expanded to start/end pairs, character and attribute
    /// escaping normalized, and namespaces rendered per the inclusive or exclusive
    /// rules. Comments are omitted unless requested. Reimplemented from the C14N
    /// specification.
    struct Canonicalizer: Sendable {
        public let options: Options

        public init(options: Options = .inclusive) {
            self.options = options
        }

        /// Canonicalizes a node.
        public func canonicalize(_ node: PureXML.Model.Node) -> String {
            var output = ""
            emit(node, inScope: [:], rendered: [:], output: &output)
            return output
        }

        private func emit(
            _ node: PureXML.Model.Node,
            inScope: [String: String],
            rendered: [String: String],
            output: inout String,
        ) {
            switch node {
            case let .document(children):
                for child in children {
                    emit(child, inScope: inScope, rendered: rendered, output: &output)
                }
            case let .element(element):
                emit(element, inScope: inScope, rendered: rendered, output: &output)
            case let .text(value), let .cdata(value):
                output += Self.escapeText(value)
            case let .comment(value):
                if options.includeComments { output += "<!--\(value)-->" }
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
            }
        }

        private func emit(
            _ element: PureXML.Model.Element,
            inScope: [String: String],
            rendered: [String: String],
            output: inout String,
        ) {
            let declarations = Self.namespaceDeclarations(element)
            var childInScope = inScope
            for (prefix, uri) in declarations {
                childInScope[prefix] = uri
            }
            let attributes = Self.plainAttributes(element)
            let toRender = namespacesToRender(element, declarations: declarations, inScope: childInScope, attributes: attributes, rendered: rendered)
            var childRendered = rendered
            for (prefix, uri) in toRender {
                childRendered[prefix] = uri
            }

            output += "<" + element.name.description
            for (prefix, uri) in toRender.sorted(by: { $0.0 < $1.0 }) {
                output += Self.renderNamespace(prefix, uri)
            }
            for attribute in attributes.sorted(by: Self.attributeOrder) {
                output += " \(attribute.name.description)=\"\(Self.escapeAttribute(attribute.value))\""
            }
            output += ">"
            for child in element.children {
                emit(child, inScope: childInScope, rendered: childRendered, output: &output)
            }
            output += "</\(element.name.description)>"
        }

        // MARK: Namespace selection

        private func namespacesToRender(
            _ element: PureXML.Model.Element,
            declarations: [(String, String)],
            inScope: [String: String],
            attributes: [PureXML.Model.Attribute],
            rendered: [String: String],
        ) -> [(String, String)] {
            switch options.mode {
            case .inclusive:
                declarations.filter { rendered[$0.0] != $0.1 }
            case .exclusive:
                exclusiveNamespaces(element, inScope: inScope, attributes: attributes, rendered: rendered)
            }
        }

        private func exclusiveNamespaces(
            _ element: PureXML.Model.Element,
            inScope: [String: String],
            attributes: [PureXML.Model.Attribute],
            rendered: [String: String],
        ) -> [(String, String)] {
            var utilized: Set<String> = [element.name.prefix ?? ""]
            for attribute in attributes where attribute.name.prefix != nil {
                utilized.insert(attribute.name.prefix ?? "")
            }
            utilized.formUnion(options.inclusiveNamespacePrefixes)

            var result: [(String, String)] = []
            for prefix in utilized {
                let uri = inScope[prefix] ?? ""
                if prefix.isEmpty {
                    if uri != (rendered[""] ?? "") { result.append(("", uri)) }
                } else if !uri.isEmpty, rendered[prefix] != uri {
                    result.append((prefix, uri))
                }
            }
            return result
        }

        // MARK: Attribute and namespace rendering

        private static func renderNamespace(_ prefix: String, _ uri: String) -> String {
            prefix.isEmpty ? " xmlns=\"\(escapeAttribute(uri))\"" : " xmlns:\(prefix)=\"\(escapeAttribute(uri))\""
        }

        private static func attributeOrder(_ lhs: PureXML.Model.Attribute, _ rhs: PureXML.Model.Attribute) -> Bool {
            let leftURI = lhs.name.namespaceURI ?? ""
            let rightURI = rhs.name.namespaceURI ?? ""
            if leftURI != rightURI { return leftURI < rightURI }
            return lhs.name.localName < rhs.name.localName
        }

        private static func namespaceDeclarations(_ element: PureXML.Model.Element) -> [(String, String)] {
            element.attributes.compactMap { attribute in
                let name = attribute.name
                if name.prefix == nil, name.localName == "xmlns" { return ("", attribute.value) }
                if name.prefix == "xmlns" { return (name.localName, attribute.value) }
                return nil
            }
        }

        private static func plainAttributes(_ element: PureXML.Model.Element) -> [PureXML.Model.Attribute] {
            element.attributes.filter { attribute in
                let name = attribute.name
                return name.prefix != "xmlns" && !(name.prefix == nil && name.localName == "xmlns")
            }
        }

        // MARK: Escaping

        private static func escapeText(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\r": result += "&#xD;"
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
                case "\t": result += "&#x9;"
                case "\n": result += "&#xA;"
                case "\r": result += "&#xD;"
                default: result.append(character)
                }
            }
            return result
        }
    }
}

public extension PureXML.Canonical {
    /// Canonicalizes a node with the given options.
    static func canonicalize(_ node: PureXML.Model.Node, options: Options = .inclusive) -> String {
        Canonicalizer(options: options).canonicalize(node)
    }
}
