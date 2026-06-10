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
            if Elements.void.contains(name.lowercased()) {
                return output
            }
            output += content(of: element, name: name)
            return output + "</\(name)>"
        }

        private static func content(of element: PureXML.Model.Element, name: String) -> String {
            if Elements.rawText.contains(name.lowercased()) {
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
            if attribute.value.isEmpty { return " \(name)" }
            // Boolean attributes minimize when the value repeats the name
            // (CHECKED="CHECKED" serializes as CHECKED), the html form.
            if Elements.booleanAttributes.contains(name.lowercased()), attribute.value.lowercased() == name.lowercased() {
                return " \(name)"
            }
            return " \(name)=\"\(escapeAttribute(attribute.value))\""
        }

        private static func escapeText(_ value: String) -> String {
            var result = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                default: result += latin1Entity(scalar) ?? String(Character(scalar))
                }
            }
            return result
        }

        private static func escapeAttribute(_ value: String) -> String {
            var result = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "&": result += "&amp;"
                case "\"": result += "&quot;"
                case "<": result += "&lt;"
                default: result += latin1Entity(scalar) ?? String(Character(scalar))
                }
            }
            return result
        }

        /// The HTML 4.01 Latin-1 named entities: U+00A0 through U+00FF map
        /// onto these names in order (the html output method's escapes).
        private static let latin1Names = [
            "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect",
            "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
            "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot",
            "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
            "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil",
            "Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml",
            "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times",
            "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
            "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil",
            "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
            "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide",
            "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
        ]

        private static func latin1Entity(_ scalar: Unicode.Scalar) -> String? {
            guard scalar.value >= 0xA0, scalar.value <= 0xFF else { return nil }
            return "&" + latin1Names[Int(scalar.value) - 0xA0] + ";"
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
