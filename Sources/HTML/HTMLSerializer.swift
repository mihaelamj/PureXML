extension PureXML.HTML {
    /// Serializes a node tree as HTML (the libxml2 `HTMLtree.h` model): void
    /// elements are written without an end tag or self-closing slash, raw-text
    /// elements (`script`, `style`) keep their content unescaped, and text and
    /// attribute values are escaped per HTML.
    enum Serializer {
        static func serialize(_ node: PureXML.Model.Node) -> String {
            switch node {
            case let .document(children):
                children.map(serialize).joined()
            case let .element(element):
                serializeElement(element)
            case let .text(value), let .cdata(value):
                escapeText(value)
            case let .comment(value):
                "<!--\(value)-->"
            case let .processingInstruction(target, data):
                data.isEmpty ? "<?\(target)>" : "<?\(target) \(data)>"
            }
        }

        private static func serializeElement(_ element: PureXML.Model.Element) -> String {
            let name = element.name.description
            var output = "<" + name
            for attribute in element.attributes {
                output += attributeText(attribute)
            }
            output += ">"
            if Elements.void.contains(name) {
                return output
            }
            output += content(of: element, name: name)
            return output + "</\(name)>"
        }

        private static func content(of element: PureXML.Model.Element, name: String) -> String {
            if Elements.rawText.contains(name) {
                return element.children.map(rawText).joined()
            }
            return element.children.map(serialize).joined()
        }

        private static func rawText(_ node: PureXML.Model.Node) -> String {
            switch node {
            case let .text(value), let .cdata(value): value
            default: serialize(node)
            }
        }

        private static func attributeText(_ attribute: PureXML.Model.Attribute) -> String {
            let name = attribute.name.description
            return attribute.value.isEmpty ? " \(name)" : " \(name)=\"\(escapeAttribute(attribute.value))\""
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
                case "\"": result += "&quot;"
                case "<": result += "&lt;"
                default: result.append(character)
                }
            }
            return result
        }
    }
}

public extension PureXML.HTML {
    /// Parses an HTML fragment into a ``PureXML/Model/Node`` document, leniently
    /// handling tag-soup input, void elements, optional end tags, and raw-text
    /// elements. Markup is taken as-is, with no implied `html`/`head`/`body`.
    static func parse(_ html: String) -> PureXML.Model.Node {
        var tokenizer = Tokenizer(html)
        return TreeBuilder.build(tokenizer.tokenize())
    }

    /// Parses a full HTML document by the HTML5 tree-construction insertion
    /// modes: the result always has an `html` root containing a `head` and a
    /// `body`, with head-only elements (`title`, `meta`, `link`, `style`,
    /// `script`, and the rest) routed into the head and flow content into the
    /// body, whether or not the source spelled those elements out.
    static func parseDocument(_ html: String) -> PureXML.Model.Node {
        var tokenizer = Tokenizer(html)
        return DocumentBuilder.build(tokenizer.tokenize())
    }

    /// Serializes a node tree as HTML.
    static func serialize(_ node: PureXML.Model.Node) -> String {
        Serializer.serialize(node)
    }
}
