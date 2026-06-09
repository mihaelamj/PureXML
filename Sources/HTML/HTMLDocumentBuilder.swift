/// A partially-built element on an open-element stack. File-scope and private.
private struct DocFrame {
    let name: String
    let attributes: [PureXML.Model.Attribute]
    var children: [PureXML.Model.Node] = []
    /// The foreign-content namespace URI (SVG or MathML) when this element is in
    /// foreign content, or nil for ordinary HTML.
    var namespace: String?
}

/// The foreign-content namespaces HTML5 switches into. File-scope and private.
private enum ForeignNamespace {
    static let svg = "http://www.w3.org/2000/svg"
    static let mathml = "http://www.w3.org/1998/Math/MathML"
}

/// The HTML5 tree-construction insertion modes this builder implements: the
/// document-structure subset that establishes the implied `html`, `head`, and
/// `body`. File-scope and private.
private enum InsertionMode {
    case initial
    case beforeHtml
    case beforeHead
    case inHead
    case afterHead
    case inBody
}

/// Builds a full HTML document from tokens by driving the HTML5 insertion modes,
/// materializing the implied `html`/`head`/`body` and routing head-only elements
/// into the head. File-scope and private.
private final class HTMLDocument {
    typealias Token = PureXML.HTML.Token
    typealias Node = PureXML.Model.Node
    typealias Attribute = PureXML.Model.Attribute

    /// Elements that belong in the head.
    private static let headElements: Set<String> = [
        "base", "basefont", "bgsound", "link", "meta", "title", "style", "script", "noscript", "noframes", "template",
    ]

    private var mode: InsertionMode = .initial
    private var htmlAttributes: [Attribute] = []
    private var headAttributes: [Attribute] = []
    private var bodyAttributes: [Attribute] = []
    private var headStack: [DocFrame] = []
    private var headChildren: [Node] = []
    private var bodyStack: [DocFrame] = []
    private var bodyChildren: [Node] = []

    func build(_ tokens: [Token]) -> Node {
        for token in tokens {
            process(token)
        }
        while !headStack.isEmpty {
            pop(&headStack, &headChildren)
        }
        while !bodyStack.isEmpty {
            pop(&bodyStack, &bodyChildren)
        }
        let head = PureXML.Model.Element(name: .init("head"), attributes: headAttributes, children: headChildren)
        let body = PureXML.Model.Element(name: .init("body"), attributes: bodyAttributes, children: bodyChildren)
        let html = PureXML.Model.Element(
            name: .init("html"),
            attributes: htmlAttributes,
            children: [.element(head), .element(body)],
        )
        return .document([.element(html)])
    }

    private func process(_ token: Token) {
        switch mode {
        case .initial: processInitial(token)
        case .beforeHtml: processBeforeHtml(token)
        case .beforeHead: processBeforeHead(token)
        case .inHead: processInHead(token)
        case .afterHead: processAfterHead(token)
        case .inBody: processInBody(token)
        }
    }

    // MARK: Document-structure modes

    private func processInitial(_ token: Token) {
        if case .doctype = token { return }
        if isIgnorableWhitespace(token) { return }
        mode = .beforeHtml
        process(token)
    }

    private func processBeforeHtml(_ token: Token) {
        if case let .startTag(name, attributes, _) = token, name == "html" {
            htmlAttributes = modelAttributes(attributes)
            mode = .beforeHead
            return
        }
        if isIgnorableWhitespace(token) { return }
        mode = .beforeHead
        process(token)
    }

    private func processBeforeHead(_ token: Token) {
        if isIgnorableWhitespace(token) { return }
        if case let .startTag(name, attributes, _) = token, name == "head" {
            headAttributes = modelAttributes(attributes)
            mode = .inHead
            return
        }
        mode = .inHead
        process(token)
    }

    private func processInHead(_ token: Token) {
        switch token {
        case let .startTag(name, attributes, selfClosing) where Self.headElements.contains(name):
            open(name, attributes, selfClosing: selfClosing, &headStack, &headChildren)
        case let .endTag(name) where name == "head":
            while !headStack.isEmpty {
                pop(&headStack, &headChildren)
            }
            mode = .afterHead
        case let .endTag(name) where headStack.contains(where: { $0.name == name }):
            close(name, &headStack, &headChildren)
        case let .comment(value):
            attach(.comment(value), &headStack, &headChildren)
        case let .text(value) where !headStack.isEmpty:
            attach(.text(value), &headStack, &headChildren)
        case let .text(value) where value.trimmingXMLWhitespace().isEmpty:
            attach(.text(value), &headStack, &headChildren)
        default:
            while !headStack.isEmpty {
                pop(&headStack, &headChildren)
            }
            mode = .afterHead
            process(token)
        }
    }

    private func processAfterHead(_ token: Token) {
        if case let .startTag(name, attributes, _) = token, name == "body" {
            bodyAttributes = modelAttributes(attributes)
            mode = .inBody
            return
        }
        if case let .startTag(name, _, _) = token, Self.headElements.contains(name) {
            mode = .inHead
            process(token)
            return
        }
        if isIgnorableWhitespace(token) { return }
        mode = .inBody
        process(token)
    }

    private func processInBody(_ token: Token) {
        switch token {
        case let .startTag(name, attributes, selfClosing):
            open(name, attributes, selfClosing: selfClosing, &bodyStack, &bodyChildren)
        case let .endTag(name) where name != "body" && name != "html":
            close(name, &bodyStack, &bodyChildren)
        case let .text(value):
            attach(.text(value), &bodyStack, &bodyChildren)
        case let .comment(value):
            attach(.comment(value), &bodyStack, &bodyChildren)
        default:
            break
        }
    }

    // MARK: Insertion primitives

    private func open(
        _ name: String,
        _ attributes: [(String, String)],
        selfClosing: Bool,
        _ stack: inout [DocFrame],
        _ roots: inout [Node],
    ) {
        if let closes = PureXML.HTML.Elements.impliedClose[name] {
            while let top = stack.last, closes.contains(top.name) {
                pop(&stack, &roots)
            }
        }
        ensureTableContext(for: name, &stack, &roots)
        let modeled = modelAttributes(attributes)
        let namespace = foreignNamespace(for: name, in: stack)
        if PureXML.HTML.Elements.void.contains(name) || selfClosing {
            attach(.element(PureXML.Model.Element(name: qualifiedName(name, namespace), attributes: modeled)), &stack, &roots)
        } else {
            stack.append(DocFrame(name: name, attributes: modeled, namespace: namespace))
        }
    }

    /// The namespace an element enters: SVG for `<svg>`, MathML for `<math>`, the
    /// namespace of the nearest open foreign ancestor for anything inside one, or
    /// nil for ordinary HTML content.
    private func foreignNamespace(for name: String, in stack: [DocFrame]) -> String? {
        if name == "svg" { return ForeignNamespace.svg }
        if name == "math" { return ForeignNamespace.mathml }
        return stack.reversed().first { $0.namespace != nil }?.namespace
    }

    /// A qualified name carrying its foreign-content namespace URI, so an SVG or
    /// MathML element is distinguishable from same-named HTML. SVG element names
    /// are restored to their canonical camel case (`foreignObject`, not the
    /// tokenizer's lowercased `foreignobject`).
    private func qualifiedName(_ name: String, _ namespace: String?) -> PureXML.Model.QualifiedName {
        let local = namespace == ForeignNamespace.svg ? (PureXML.HTML.ForeignNames.svgElements[name] ?? name) : name
        return PureXML.Model.QualifiedName(prefix: nil, localName: local, namespaceURI: namespace)
    }

    /// HTML table tree construction: a `<tr>` inside a bare `<table>` gets an
    /// implied `<tbody>`, and a `<td>`/`<th>` gets an implied `<tr>` (and section),
    /// so a table written without its section and row wrappers still nests
    /// correctly. Only fires inside an open table.
    private func ensureTableContext(for name: String, _ stack: inout [DocFrame], _: inout [Node]) {
        guard let context = nearestTableContext(stack) else { return }
        switch name {
        case "tr" where context == "table":
            stack.append(DocFrame(name: "tbody", attributes: []))
        case "td", "th":
            if context == "table" { stack.append(DocFrame(name: "tbody", attributes: [])) }
            if context == "table" || ["tbody", "thead", "tfoot"].contains(context) {
                stack.append(DocFrame(name: "tr", attributes: []))
            }
        default:
            break
        }
    }

    /// The nearest open table-structural element (`table`/`tbody`/`thead`/`tfoot`/
    /// `tr`), or nil when no table is open.
    private func nearestTableContext(_ stack: [DocFrame]) -> String? {
        let structural: Set = ["table", "tbody", "thead", "tfoot", "tr"]
        return stack.reversed().first { structural.contains($0.name) }?.name
    }

    private func close(_ name: String, _ stack: inout [DocFrame], _ roots: inout [Node]) {
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        while stack.count > index {
            pop(&stack, &roots)
        }
    }

    private func pop(_ stack: inout [DocFrame], _ roots: inout [Node]) {
        guard let frame = stack.popLast() else { return }
        let element = PureXML.Model.Element(name: qualifiedName(frame.name, frame.namespace), attributes: frame.attributes, children: frame.children)
        attach(.element(element), &stack, &roots)
    }

    private func attach(_ node: Node, _ stack: inout [DocFrame], _ roots: inout [Node]) {
        if stack.isEmpty {
            roots.append(node)
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }

    private func modelAttributes(_ attributes: [(String, String)]) -> [Attribute] {
        attributes.map { Attribute($0.0, $0.1) }
    }

    private func isIgnorableWhitespace(_ token: Token) -> Bool {
        if case let .text(value) = token { return value.trimmingXMLWhitespace().isEmpty }
        return false
    }
}

extension PureXML.HTML {
    /// Builds a full HTML document tree from tokens via the insertion modes.
    enum DocumentBuilder {
        static func build(_ tokens: [Token]) -> PureXML.Model.Node {
            HTMLDocument().build(tokens)
        }
    }
}
