/// One XInclude pass over a value tree. File-scope and private: an internal
/// detail of ``PureXML/XInclude``. Operates on the immutable ``PureXML/Model/Node``
/// tree, returning a new tree with `xi:include` elements replaced.
private struct XIncludeRun {
    typealias Node = PureXML.Model.Node
    typealias Element = PureXML.Model.Element

    let load: (String) -> String?
    let maxDepth = 30
    let namespace = "http://www.w3.org/2001/XInclude"

    func process(_ node: Node, base: String, depth: Int) throws -> [Node] {
        switch node {
        case let .document(children):
            try [.document(children.flatMap { try process($0, base: base, depth: depth) })]
        case let .element(element):
            try processElement(element, base: base, depth: depth)
        default:
            [node]
        }
    }

    private func processElement(_ element: Element, base: String, depth: Int) throws -> [Node] {
        if isInclude(element) {
            return try resolveInclude(element, base: base, depth: depth)
        }
        let elementBase = baseURI(of: element, base: base)
        let children = try element.children.flatMap { try process($0, base: elementBase, depth: depth) }
        return [.element(Element(name: element.name, attributes: element.attributes, children: children))]
    }

    private func resolveInclude(_ element: Element, base: String, depth: Int) throws -> [Node] {
        guard depth < maxDepth else { throw PureXML.XInclude.XIncludeError.toodeep }
        let elementBase = baseURI(of: element, base: base)
        guard let href = attribute(element, "href") else {
            return try fallback(element, base: base, depth: depth, error: .missingHref)
        }
        let resolved = PureXML.XInclude.URIReference.resolve(href, against: elementBase)
        guard let content = load(resolved) else {
            return try fallback(element, base: base, depth: depth, error: .unresolved(href))
        }
        if attribute(element, "parse") == "text" {
            return [.text(content)]
        }
        guard let parsed = try? PureXML.parse(content) else {
            return try fallback(element, base: base, depth: depth, error: .unresolved(href))
        }
        let selected = selectedNodes(from: parsed, xpointer: attribute(element, "xpointer"))
        return try selected.flatMap { try process($0, base: resolved, depth: depth + 1) }
    }

    private func selectedNodes(from parsed: Node, xpointer: String?) -> [Node] {
        if let xpointer {
            let selections = (try? PureXML.XPointer.evaluate(xpointer, over: parsed)) ?? []
            return selections.map(Self.node)
        }
        return [documentElement(of: parsed) ?? parsed]
    }

    private func documentElement(of parsed: Node) -> Node? {
        guard case let .document(children) = parsed else { return nil }
        return children.first { if case .element = $0 { true } else { false } }
    }

    private static func node(_ selection: PureXML.XPath.Selection) -> Node {
        switch selection {
        case let .node(node): node
        case let .attribute(attribute): .text(attribute.value)
        }
    }

    private func fallback(
        _ element: Element,
        base: String,
        depth: Int,
        error: PureXML.XInclude.XIncludeError,
    ) throws -> [Node] {
        guard let fallback = element.children.first(where: isFallback),
              case let .element(fallbackElement) = fallback
        else {
            throw error
        }
        return try fallbackElement.children.flatMap { try process($0, base: base, depth: depth) }
    }

    private func baseURI(of element: Element, base: String) -> String {
        guard let declared = attribute(element, "xml:base") else { return base }
        return PureXML.XInclude.URIReference.resolve(declared, against: base)
    }

    private func isInclude(_ element: Element) -> Bool {
        element.name.localName == "include" && inXIncludeNamespace(element)
    }

    private func isFallback(_ node: Node) -> Bool {
        guard case let .element(element) = node else { return false }
        return element.name.localName == "fallback" && inXIncludeNamespace(element)
    }

    private func inXIncludeNamespace(_ element: Element) -> Bool {
        element.name.namespaceURI == namespace || element.name.prefix == "xi"
    }

    private func attribute(_ element: Element, _ name: String) -> String? {
        element.attributes.first { $0.name.description == name }?.value
    }
}

public extension PureXML.XInclude {
    /// Processes the `xi:include` elements in a parsed tree, returning a new tree
    /// with each include replaced by its target's content. `href`s are resolved
    /// against `base` and the in-scope `xml:base`, then loaded through
    /// `loadingURI`. PureXML performs no I/O itself: a reference whose loader
    /// returns nil falls back to the include's `xi:fallback`, or errors if there
    /// is none. With a loader that always returns nil nothing external is fetched.
    static func process(
        _ node: PureXML.Model.Node,
        base: String = "",
        loadingURI: @escaping (_ uri: String) -> String?,
    ) throws -> PureXML.Model.Node {
        let run = XIncludeRun(load: loadingURI)
        return try run.process(node, base: base, depth: 0).first ?? node
    }

    /// Parses `xml` and processes its `xi:include` elements.
    static func process(
        _ xml: String,
        base: String = "",
        loadingURI: @escaping (_ uri: String) -> String?,
    ) throws -> PureXML.Model.Node {
        try process(PureXML.parse(xml), base: base, loadingURI: loadingURI)
    }
}
