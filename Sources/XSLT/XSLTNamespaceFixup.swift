/// Namespace fixup over an XSLT result tree (the serialization step of
/// XSLT 1.0 section 7.1): every element and attribute name that carries a
/// namespace URI gets an in-scope declaration, with `ns0`, `ns1`, ... prefixes
/// generated when the carried prefix is absent or bound to a different URI.
enum XSLTNamespaceFixup {
    static func apply(_ node: PureXML.Model.Node) -> PureXML.Model.Node {
        var counter = 0
        return fix(node, inScope: ["xml": "http://www.w3.org/XML/1998/namespace"], counter: &counter)
    }

    /// Declarations the element already carries enter scope first.
    private static func enterDeclarations(_ attributes: [PureXML.Model.Attribute], into scope: inout [String: String]) {
        for attribute in attributes {
            if attribute.name.prefix == "xmlns" {
                scope[attribute.name.localName] = attribute.value
            } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                scope[""] = attribute.value
            }
        }
    }

    /// Declares the element's own namespace, or undeclares an inherited
    /// default that would capture an unqualified name.
    private static func fixElementName(_ name: PureXML.Model.QualifiedName, scope: inout [String: String], attributes: inout [PureXML.Model.Attribute]) {
        if let uri = name.namespaceURI, !uri.isEmpty {
            let prefix = name.prefix ?? ""
            if scope[prefix] != uri {
                scope[prefix] = uri
                attributes.append(.init(prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)", uri))
            }
        } else if name.namespaceURI == nil, name.prefix == nil, let inherited = scope[""], !inherited.isEmpty {
            scope[""] = ""
            attributes.append(.init("xmlns", ""))
        }
    }

    /// A namespaced attribute needs a prefix bound to its URI, generated
    /// fresh when absent or taken by a different binding.
    private static func fixAttributeName(at index: Int, attributes: inout [PureXML.Model.Attribute], scope: inout [String: String], counter: inout Int) {
        let attributeName = attributes[index].name
        guard let uri = attributeName.namespaceURI, !uri.isEmpty,
              attributeName.prefix != "xmlns", attributeName.prefix != "xml"
        else { return }
        var prefix = attributeName.prefix
        if let candidate = prefix, scope[candidate] == uri {
            return // Already bound correctly.
        }
        if prefix == nil || scope[prefix ?? ""] != nil {
            if let existing = scope.first(where: { $0.value == uri && !$0.key.isEmpty })?.key {
                prefix = existing
            } else {
                while scope["ns\(counter)"] != nil {
                    counter += 1
                }
                prefix = "ns\(counter)"
                counter += 1
            }
        }
        guard let resolved = prefix else { return }
        if scope[resolved] != uri {
            scope[resolved] = uri
            attributes.append(.init("xmlns:\(resolved)", uri))
        }
        attributes[index] = .init(
            name: .init(prefix: resolved, localName: attributeName.localName, namespaceURI: uri),
            value: attributes[index].value,
        )
    }

    /// A prefix bound to `uri`: the carried one when free, an existing
    /// binding for the same URI, or a fresh `ns<n>`.
    private static func resolvedPrefix(for uri: String, carried: String?, scope: [String: String], counter: inout Int) -> String {
        if let carried, scope[carried] == nil { return carried }
        if let existing = scope.first(where: { $0.value == uri && !$0.key.isEmpty })?.key {
            return existing
        }
        var fresh = counter
        while scope["ns\(fresh)"] != nil {
            fresh += 1
        }
        counter = fresh + 1
        return "ns\(fresh)"
    }

    private static func fix(_ node: PureXML.Model.Node, inScope: [String: String], counter: inout Int) -> PureXML.Model.Node {
        switch node {
        case let .document(children):
            .document(children.map { fix($0, inScope: inScope, counter: &counter) })
        case let .element(element):
            .element(fix(element, inScope: inScope, counter: &counter))
        default:
            node
        }
    }

    private static func fix(_ element: PureXML.Model.Element, inScope: [String: String], counter: inout Int) -> PureXML.Model.Element {
        var scope = inScope
        var attributes = element.attributes
        enterDeclarations(attributes, into: &scope)
        fixElementName(element.name, scope: &scope, attributes: &attributes)
        // Attribute names: a namespaced attribute always needs a prefix.
        for index in attributes.indices {
            let attributeName = attributes[index].name
            guard let uri = attributeName.namespaceURI, !uri.isEmpty,
                  attributeName.prefix != "xmlns", attributeName.prefix != "xml"
            else { continue }
            var prefix = attributeName.prefix
            if let candidate = prefix, scope[candidate] == uri {
                continue // Already bound correctly.
            }
            if prefix == nil || scope[prefix ?? ""] != nil {
                // Generate a fresh prefix when absent or taken by another URI.
                if let existing = scope.first(where: { $0.value == uri && !$0.key.isEmpty })?.key {
                    prefix = existing
                } else {
                    while scope["ns\(counter)"] != nil {
                        counter += 1
                    }
                    prefix = "ns\(counter)"
                    counter += 1
                }
            }
            guard let resolved = prefix else { continue }
            if scope[resolved] != uri {
                scope[resolved] = uri
                attributes.append(.init("xmlns:\(resolved)", uri))
            }
            attributes[index] = .init(
                name: .init(prefix: resolved, localName: attributeName.localName, namespaceURI: uri),
                value: attributes[index].value,
            )
        }
        let children = element.children.map { fix($0, inScope: scope, counter: &counter) }
        return .init(name: element.name, attributes: attributes, children: children)
    }
}
