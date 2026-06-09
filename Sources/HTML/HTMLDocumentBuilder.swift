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
/// into the head. The adoption agency lives in a sibling file, so this type is
/// internal (its members stay private except the live-body state it shares).
final class HTMLDocument {
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
    /// The body is built as a live mutable tree (the HTML5 model): nodes are
    /// attached to their parent as soon as they open, and `openBody` is the stack
    /// of currently-open elements into that tree, with the body element at the
    /// bottom. This lets the adoption agency reparent already-built subtrees, which
    /// a pop-on-close model cannot.
    let bodyRoot = PureXML.Model.TreeNode.element("body")
    lazy var openBody: [PureXML.Model.TreeNode] = [bodyRoot]
    /// The active formatting elements (the HTML5 list), with nil entries acting as
    /// scope markers. Drives reconstruction and the adoption agency.
    var activeFormatting: [PureXML.Model.TreeNode?] = []

    func build(_ tokens: [Token]) -> Node {
        for token in tokens {
            process(token)
        }
        while !headStack.isEmpty {
            pop(&headStack, &headChildren)
        }
        // Open body elements are already attached to the live tree, so no closing
        // pass is needed: the body's children are read straight off bodyRoot.
        let head = PureXML.Model.Element(name: .init("head"), attributes: headAttributes, children: headChildren)
        let body = PureXML.Model.Element(name: .init("body"), attributes: bodyAttributes, children: bodyRoot.children.map(\.node))
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
            reconstructActiveFormatting()
            bodyOpen(name, attributes, selfClosing: selfClosing)
            noteOpenedFormatting(name, selfClosing: selfClosing)
        case let .endTag(name) where isFormatting(name):
            adoptionAgency(name)
        case let .endTag(name) where name != "body" && name != "html":
            bodyClose(name)
        case let .text(value):
            reconstructActiveFormatting()
            bodyInsert(.text(value))
        case let .comment(value):
            bodyInsert(.comment(value))
        default:
            break
        }
    }

    /// After opening a start tag, records it on the active-formatting list when it
    /// is a formatting element (so misnesting can be recovered later).
    private func noteOpenedFormatting(_ name: String, selfClosing: Bool) {
        guard isFormatting(name), !selfClosing, !PureXML.HTML.Elements.void.contains(name), let opened = openBody.last else { return }
        activeFormatting.append(opened)
    }

    // MARK: Body building (live mutable tree)

    /// The lowercased tag name of an open element, for case-insensitive stack
    /// matching (an SVG element's canonical camel case folds back to the token).
    func tagName(_ node: PureXML.Model.TreeNode) -> String {
        node.name?.localName.lowercased() ?? ""
    }

    private func bodyOpen(_ name: String, _ attributes: [(String, String)], selfClosing: Bool) {
        if let closes = PureXML.HTML.Elements.impliedClose[name] {
            while let top = openBody.last, top !== bodyRoot, closes.contains(tagName(top)) {
                openBody.removeLast()
            }
        }
        bodyEnsureTableContext(for: name)
        let namespace = bodyForeignNamespace(for: name)
        let element = PureXML.Model.TreeNode.element(qualifiedName(name, namespace), attributes: adjustedAttributes(modelAttributes(attributes), namespace: namespace))
        openBody.last?.append(element)
        if !(PureXML.HTML.Elements.void.contains(name) || selfClosing) {
            openBody.append(element)
        }
    }

    func bodyClose(_ name: String) {
        guard let index = openBody.lastIndex(where: { tagName($0) == name }), index >= 1 else { return }
        openBody.removeLast(openBody.count - index)
    }

    private func bodyInsert(_ node: PureXML.Model.TreeNode) {
        openBody.last?.append(node)
    }

    /// The table-construction implied insertions, against the live body stack.
    private func bodyEnsureTableContext(for name: String) {
        let structural: Set = ["table", "tbody", "thead", "tfoot", "tr"]
        guard let context = openBody.reversed().first(where: { structural.contains(tagName($0)) }).map(tagName) else { return }
        switch name {
        case "tr" where context == "table":
            bodyPushImplied("tbody")
        case "td", "th":
            if context == "table" { bodyPushImplied("tbody") }
            if context == "table" || ["tbody", "thead", "tfoot"].contains(context) { bodyPushImplied("tr") }
        default:
            break
        }
    }

    private func bodyPushImplied(_ name: String) {
        let element = PureXML.Model.TreeNode.element(name)
        openBody.last?.append(element)
        openBody.append(element)
    }

    /// Restores SVG attribute names to their canonical camel case (`viewBox`, not
    /// the tokenizer's `viewbox`) for elements in the SVG namespace.
    private func adjustedAttributes(_ attributes: [Attribute], namespace: String?) -> [Attribute] {
        guard namespace == ForeignNamespace.svg else { return attributes }
        return attributes.map { attribute in
            guard let adjusted = PureXML.HTML.ForeignNames.svgAttributes[attribute.name.localName.lowercased()] else { return attribute }
            return Attribute(adjusted, attribute.value)
        }
    }

    /// The foreign-content namespace for a body element: SVG/MathML on entry, or
    /// the nearest open foreign ancestor's namespace inside one.
    private func bodyForeignNamespace(for name: String) -> String? {
        if name == "svg" { return ForeignNamespace.svg }
        if name == "math" { return ForeignNamespace.mathml }
        return openBody.reversed().compactMap { $0.name?.namespaceURI }.first
    }
}

/// The head's open-element stack still uses the pop-on-close `DocFrame` model (it
/// needs no adoption agency); these primitives drive it, kept in an extension so
/// the class body stays within its size budget.
extension HTMLDocument {
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
