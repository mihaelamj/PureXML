/// One XInclude pass over a value tree. File-scope and private: an internal
/// detail of ``PureXML/XInclude``. Operates on the immutable ``PureXML/Model/Node``
/// tree, returning a new tree with `xi:include` elements replaced.
/// The in-scope context threaded down an XInclude pass: the `xml:base` for
/// resolving hrefs, the inclusion-chain `depth` (bounded by `maxDepth`), and the
/// `visited` resources that detect a cycle.
private struct XIncludeContext {
    let base: String
    let depth: Int
    let visited: Set<String>
}

/// A mutable bag of processed nodes a branch's children gather into, so the
/// deferred build step assembles the parent once they are done.
private final class XIncludeAccumulator {
    var nodes: [PureXML.Model.Node] = []
}

/// One unit of XInclude work: visit a source node (appending its processed result
/// to `target`), or, after a branch's children are gathered, build the element or
/// document and append it to `target`. File-scoped to keep the work stack off the
/// type-nesting depth.
private enum XIncludeWork {
    case visit(PureXML.Model.Node, XIncludeContext, XIncludeAccumulator)
    case buildElement(PureXML.Model.Element, XIncludeAccumulator, XIncludeAccumulator)
    case buildDocument(XIncludeAccumulator, XIncludeAccumulator)
}

private struct XIncludeRun {
    typealias Node = PureXML.Model.Node
    typealias Element = PureXML.Model.Element

    typealias Request = PureXML.XInclude.XIncludeRequest

    let load: (Request) -> String?
    let maxDepth = 30
    let namespace = "http://www.w3.org/2001/XInclude"

    /// Rebuilds the tree with `xi:include` elements replaced, without recursing on
    /// the tree's depth: an explicit work stack drives a post-order rebuild so a
    /// deeply-nested document does not overflow the stack. Each branch gathers its
    /// processed children into a reference accumulator, then a deferred build step
    /// assembles the node once those children are done. `base` (the in-scope
    /// `xml:base`) threads down per element; `depth` (the inclusion-chain depth,
    /// bounded by `maxDepth`) and `visited` (the cycle set) advance only across an
    /// include boundary, exactly as the recursive form did.
    func process(_ root: Node, base: String) throws -> [Node] {
        let rootResult = XIncludeAccumulator()
        var stack: [XIncludeWork] = [.visit(root, XIncludeContext(base: base, depth: 0, visited: []), rootResult)]
        while let work = stack.popLast() {
            switch work {
            case let .visit(node, context, target):
                try visit(node, context, into: target, stack: &stack)
            case let .buildElement(element, children, target):
                target.nodes.append(.element(Element(name: element.name, attributes: element.attributes, children: children.nodes)))
            case let .buildDocument(children, target):
                target.nodes.append(.document(children.nodes))
            }
        }
        return rootResult.nodes
    }

    /// Processes one node into `target`. A branch pushes its build step first, then
    /// its children reversed, so the children pop in document order and the build
    /// runs after them.
    private func visit(_ node: Node, _ context: XIncludeContext, into target: XIncludeAccumulator, stack: inout [XIncludeWork]) throws {
        switch node {
        case let .document(children):
            let gathered = XIncludeAccumulator()
            stack.append(.buildDocument(gathered, target))
            for child in children.reversed() {
                stack.append(.visit(child, context, gathered))
            }
        case let .element(element):
            if isInclude(element) {
                try resolveInclude(element, context, into: target, stack: &stack)
            } else {
                let elementBase = baseURI(of: element, base: context.base)
                let childContext = XIncludeContext(base: elementBase, depth: context.depth, visited: context.visited)
                let gathered = XIncludeAccumulator()
                stack.append(.buildElement(element, gathered, target))
                for child in element.children.reversed() {
                    stack.append(.visit(child, childContext, gathered))
                }
            }
        default:
            target.nodes.append(node)
        }
    }

    /// Replaces an `xi:include` with its target, pushing the included (or fallback)
    /// content onto the stack to be processed into `target` in place. The included
    /// content advances the inclusion chain (`depth + 1`, base reset to the
    /// resource, the resource added to `visited`); fallback content stays in the
    /// include's own context, matching the recursive form.
    private func resolveInclude(_ element: Element, _ context: XIncludeContext, into target: XIncludeAccumulator, stack: inout [XIncludeWork]) throws {
        guard context.depth < maxDepth else { throw PureXML.XInclude.XIncludeError.toodeep }
        let elementBase = baseURI(of: element, base: context.base)
        guard let href = attribute(element, "href") else {
            try pushFallback(element, context, into: target, error: .missingHref, stack: &stack)
            return
        }
        let resolved = PureXML.XInclude.URIReference.resolve(href, against: elementBase)
        let isText = attribute(element, "parse") == "text"
        let xpointer = attribute(element, "xpointer")
        if isText, xpointer != nil { throw PureXML.XInclude.XIncludeError.textWithFragment }
        // A resource already on its own inclusion chain is a cycle.
        guard !context.visited.contains(resolved) else { throw PureXML.XInclude.XIncludeError.cycle(resolved) }
        guard let content = load(request(element, uri: resolved, isText: isText)) else {
            try pushFallback(element, context, into: target, error: .unresolved(href), stack: &stack)
            return
        }
        if isText {
            target.nodes.append(.text(content))
            return
        }
        guard let parsed = try? PureXML.parse(content) else {
            try pushFallback(element, context, into: target, error: .unresolved(href), stack: &stack)
            return
        }
        let selected = selectedNodes(from: parsed, xpointer: xpointer)
        let includedContext = XIncludeContext(base: resolved, depth: context.depth + 1, visited: context.visited.union([resolved]))
        for node in selected.reversed() {
            stack.append(.visit(node, includedContext, target))
        }
    }

    private func request(_ element: Element, uri: String, isText: Bool) -> Request {
        Request(
            uri: uri,
            accept: attribute(element, "accept"),
            acceptLanguage: attribute(element, "accept-language"),
            encoding: isText ? attribute(element, "encoding") : nil,
            isText: isText,
        )
    }

    private func selectedNodes(from parsed: Node, xpointer: String?) -> [Node] {
        guard let xpointer else { return [documentElement(of: parsed) ?? parsed] }
        let selections = (try? PureXML.XPointer.evaluate(xpointer, over: parsed)) ?? []
        if !selections.isEmpty { return selections.map(Self.node) }
        // No node-selecting scheme matched: fall back to the XPointer range model
        // (range()/range-to()/string-range()) and include each range's content.
        let ranges = (try? PureXML.XPointer.evaluateRanges(xpointer, over: parsed)) ?? []
        return ranges.flatMap(\.nodes)
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

    private func pushFallback(
        _ element: Element,
        _ context: XIncludeContext,
        into target: XIncludeAccumulator,
        error: PureXML.XInclude.XIncludeError,
        stack: inout [XIncludeWork],
    ) throws {
        guard let fallback = element.children.first(where: isFallback),
              case let .element(fallbackElement) = fallback
        else {
            throw error
        }
        for child in fallbackElement.children.reversed() {
            stack.append(.visit(child, context, target))
        }
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
        try process(node, base: base) { loadingURI($0.uri) }
    }

    /// Parses `xml` and processes its `xi:include` elements.
    static func process(
        _ xml: String,
        base: String = "",
        loadingURI: @escaping (_ uri: String) -> String?,
    ) throws -> PureXML.Model.Node {
        try process(PureXML.parse(xml), base: base, loadingURI: loadingURI)
    }

    /// Processes `xi:include` elements with a content-negotiation-aware loader: the
    /// loader receives an ``XIncludeRequest`` carrying the resolved URI plus the
    /// include's `accept`, `accept-language`, and (for `parse="text"`) `encoding`
    /// hints, and returns the loaded text or nil to fall back. A resource included
    /// along its own inclusion chain raises ``XIncludeError/cycle(_:)``; a
    /// `parse="text"` include carrying an `xpointer` raises
    /// ``XIncludeError/textWithFragment``.
    static func process(
        _ node: PureXML.Model.Node,
        base: String = "",
        loading: @escaping (_ request: XIncludeRequest) -> String?,
    ) throws -> PureXML.Model.Node {
        let run = XIncludeRun(load: loading)
        return try run.process(node, base: base).first ?? node
    }

    /// Parses `xml` and processes its `xi:include` elements with a
    /// content-negotiation-aware loader. See ``process(_:base:loading:)-(Node,_,_)``.
    static func process(
        _ xml: String,
        base: String = "",
        loading: @escaping (_ request: XIncludeRequest) -> String?,
    ) throws -> PureXML.Model.Node {
        try process(PureXML.parse(xml), base: base, loading: loading)
    }
}
