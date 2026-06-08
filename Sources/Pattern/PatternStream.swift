public extension PureXML.Pattern {
    /// Streams `xml` through the pull parser and returns the paths of every node
    /// that matches `pattern`, in document order, without building a tree. Each
    /// path is rendered root-first as `/a/b/c`, and an attribute match as
    /// `/a/b/@id`. The match is decided from the open-element stack alone, so the
    /// document is never held whole.
    static func matches(
        _ pattern: String,
        in xml: String,
        limits: PureXML.Parsing.Limits = .default,
    ) throws -> [String] {
        let matcher = try Matcher(pattern)
        return try matcher.matches(in: xml, limits: limits)
    }
}

public extension PureXML.Pattern.Matcher {
    /// Streams `xml` and returns the matching node paths in document order.
    func matches(
        in xml: String,
        limits: PureXML.Parsing.Limits = .default,
    ) throws -> [String] {
        var reader = PureXML.Parsing.EventReader(xml, limits: limits)
        var stack: [PureXML.Model.QualifiedName] = []
        var results: [String] = []
        while let event = try reader.next() {
            switch event {
            case let .startElement(name, attributes):
                stack.append(name)
                collect(stack: stack, attributes: attributes, into: &results)
            case .endElement:
                if !stack.isEmpty { stack.removeLast() }
            default:
                break
            }
        }
        return results
    }

    private func collect(
        stack: [PureXML.Model.QualifiedName],
        attributes: [PureXML.Model.Attribute],
        into results: inout [String],
    ) {
        let base = "/" + stack.map(\.description).joined(separator: "/")
        if matchesAttributes {
            for attribute in matchingAttributes(path: stack, attributes: attributes) {
                results.append(base + "/@" + attribute.name.description)
            }
        } else if matchesElement(path: stack) {
            results.append(base)
        }
    }
}
