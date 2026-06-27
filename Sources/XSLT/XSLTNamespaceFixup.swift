/// A mutable bag of fixed-up nodes a branch's children gather into, so the
/// deferred build step assembles the parent once they are done.
private final class FixupAccumulator {
    var nodes: [PureXML.Model.Node] = []
}

/// One unit of namespace-fixup work: visit a source node (with the namespace
/// bindings in scope, appending its fixed form to `into`), or, after a branch's
/// children are gathered, build the element or document.
private enum FixupWork {
    case visit(PureXML.Model.Node, inScope: [String: String], into: FixupAccumulator)
    case buildElement(PureXML.Model.QualifiedName, [PureXML.Model.Attribute], FixupAccumulator, FixupAccumulator)
    case buildDocument(FixupAccumulator, FixupAccumulator)
}

/// Namespace fixup over an XSLT result tree (the serialization step of
/// XSLT 1.0 section 7.1): every element and attribute name that carries a
/// namespace URI gets an in-scope declaration, with `ns0`, `ns1`, ... prefixes
/// generated when the carried prefix is absent or bound to a different URI.
enum XSLTNamespaceFixup {
    private static let xmlNamespace = "http://www.w3.org/XML/1998/namespace"

    /// Rebuilds the tree with namespace declarations fixed, without recursing on
    /// its depth: an explicit work stack drives a pre-order visit (so the `ns0`,
    /// `ns1`, ... counter advances in document order, exactly as the recursive form
    /// did) that gathers each branch's fixed children into an accumulator a
    /// deferred build step assembles.
    static func apply(_ node: PureXML.Model.Node) -> PureXML.Model.Node {
        var counter = 0
        let root = FixupAccumulator()
        var stack: [FixupWork] = [.visit(node, inScope: ["xml": xmlNamespace], into: root)]
        while let work = stack.popLast() {
            switch work {
            case let .visit(node, inScope, into):
                switch node {
                case let .document(children):
                    let gathered = FixupAccumulator()
                    stack.append(.buildDocument(gathered, into))
                    for child in children.reversed() {
                        stack.append(.visit(child, inScope: inScope, into: gathered))
                    }
                case let .element(element):
                    let (attributes, childScope) = fixElement(element, inScope: inScope, counter: &counter)
                    let gathered = FixupAccumulator()
                    stack.append(.buildElement(element.name, attributes, gathered, into))
                    for child in element.children.reversed() {
                        stack.append(.visit(child, inScope: childScope, into: gathered))
                    }
                default:
                    into.nodes.append(node)
                }
            case let .buildElement(name, attributes, gathered, into):
                into.nodes.append(.element(.init(name: name, attributes: attributes, children: gathered.nodes)))
            case let .buildDocument(gathered, into):
                into.nodes.append(.document(gathered.nodes))
            }
        }
        return root.nodes.first ?? node
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

    /// Drops declarations that repeat an inherited binding: copied 7.1.1
    /// namespace nodes travel on every literal element and would otherwise
    /// redeclare on each descendant.
    private static func withoutRedundantDeclarations(_ attributes: [PureXML.Model.Attribute], inScope: [String: String]) -> [PureXML.Model.Attribute] {
        attributes.filter { attribute in
            if attribute.name.prefix == "xmlns" {
                return inScope[attribute.name.localName] != attribute.value
            }
            if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                return (inScope[""] ?? "") != attribute.value
            }
            return true
        }
    }

    /// Fixes an element's own attributes and computes the namespace scope its
    /// children inherit (the per-element work of the fixup, without recursing into
    /// the children). The `ns0`, `ns1`, ... counter advances here, in visit order.
    private static func fixElement(
        _ element: PureXML.Model.Element,
        inScope: [String: String],
        counter: inout Int,
    ) -> (attributes: [PureXML.Model.Attribute], scope: [String: String]) {
        var scope = inScope
        var attributes = withoutRedundantDeclarations(element.attributes, inScope: inScope)
        enterDeclarations(attributes, into: &scope)
        // The prefixes this element itself declares: a carried prefix may
        // shadow an inherited binding, but not one declared locally.
        var localPrefixes = Set(attributes.filter { $0.name.prefix == "xmlns" }.map(\.name.localName))
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
            if let candidate = prefix, !localPrefixes.contains(candidate), element.name.prefix != candidate {
                // Redeclare the carried prefix locally, shadowing any inherited
                // binding. The element's own prefix is never shadowed.
                localPrefixes.insert(candidate)
            } else if prefix == nil || scope[prefix ?? ""] != nil {
                // Generate a fresh prefix when absent or taken locally.
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
        return (attributes, scope)
    }
}
