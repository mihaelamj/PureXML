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
    case inFrameset
    case afterFrameset
}

/// Builds a full HTML document from tokens by driving the HTML5 insertion modes,
/// materializing the implied `html`/`head`/`body` and routing head-only elements
/// into the head. The adoption agency lives in a sibling file, so this type is
/// internal (its members stay private except the live-body state it shares).
final class HTMLDocument {
    typealias Token = PureXML.HTML.Token
    typealias Node = PureXML.Model.Node
    typealias Attribute = PureXML.Model.Attribute

    /// Elements that belong in the head (`template` is excluded: it nests in body).
    private static let headElements: Set<String> = [
        "base", "basefont", "bgsound", "link", "meta", "title", "style", "script", "noscript", "noframes",
    ]

    private var mode: InsertionMode = .initial
    private var htmlAttributes: [Attribute] = []
    private var headAttributes: [Attribute] = []
    private var bodyAttributes: [Attribute] = []
    private let headRoot = PureXML.Model.TreeNode.element("head")
    private lazy var openHead: [PureXML.Model.TreeNode] = [headRoot]
    /// The body is built as a live mutable tree (the HTML5 model): nodes are
    /// attached to their parent as soon as they open, and `openBody` is the stack
    /// of currently-open elements into that tree, with the body element at the
    /// bottom. This lets the adoption agency reparent already-built subtrees, which
    /// a pop-on-close model cannot.
    let bodyRoot = PureXML.Model.TreeNode.element("body")
    lazy var openBody: [PureXML.Model.TreeNode] = [bodyRoot]
    /// The active formatting elements (HTML5 list); nil entries are scope markers.
    var activeFormatting: [PureXML.Model.TreeNode?] = []
    /// A frameset document's `frameset` stack; when non-empty its root is the body.
    private var framesetStack: [PureXML.Model.TreeNode] = []

    func build(_ tokens: [Token]) -> Node {
        for token in tokens {
            process(token)
        }
        // Open elements are already attached to their live tree, so head and body
        // children are read straight off their roots with no closing pass.
        let head = PureXML.Model.Element(name: .init("head"), attributes: headAttributes, children: headRoot.children.map(\.node))
        let secondChild: Node = if let frameset = framesetStack.first {
            frameset.node
        } else {
            .element(PureXML.Model.Element(name: .init("body"), attributes: bodyAttributes, children: bodyRoot.children.map(\.node)))
        }
        let html = PureXML.Model.Element(
            name: .init("html"),
            attributes: htmlAttributes,
            children: [.element(head), secondChild],
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
        case .inFrameset: processInFrameset(token)
        case .afterFrameset: break
        }
    }

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
            headOpen(name, attributes, selfClosing: selfClosing)
        case .endTag("head"):
            openHead = [headRoot]
            mode = .afterHead
        case let .endTag(name) where openHead.contains(where: { tagName($0) == name }):
            headClose(name)
        case let .comment(value):
            headInsert(.comment(value))
        case let .text(value) where openHead.count > 1 || value.trimmingXMLWhitespace().isEmpty:
            headInsert(.text(value))
        default:
            openHead = [headRoot]
            mode = .afterHead
            process(token)
        }
    }

    private func headOpen(_ name: String, _ attributes: [(String, String)], selfClosing: Bool) {
        if let closes = PureXML.HTML.Elements.impliedClose[name] {
            while let top = openHead.last, top !== headRoot, closes.contains(tagName(top)) {
                openHead.removeLast()
            }
        }
        let element = PureXML.Model.TreeNode.element(name, attributes: modelAttributes(attributes))
        openHead.last?.append(element)
        if !(PureXML.HTML.Elements.void.contains(name) || selfClosing) { openHead.append(element) }
    }

    private func headClose(_ name: String) {
        guard let index = openHead.lastIndex(where: { tagName($0) == name }), index >= 1 else { return }
        openHead.removeLast(openHead.count - index)
    }

    private func headInsert(_ node: PureXML.Model.TreeNode) {
        openHead.last?.append(node)
    }

    private func processAfterHead(_ token: Token) {
        if case let .startTag(name, attributes, _) = token, name == "frameset" {
            framesetStack = [PureXML.Model.TreeNode.element("frameset", attributes: modelAttributes(attributes))]
            mode = .inFrameset
            return
        }
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
            placeText(.text(value))
        case let .comment(value):
            bodyInsert(.comment(value))
        default:
            break
        }
    }

    /// Records a just-opened formatting element on the active-formatting list.
    private func noteOpenedFormatting(_ name: String, selfClosing: Bool) {
        guard isFormatting(name), !selfClosing, !PureXML.HTML.Elements.void.contains(name), let opened = openBody.last else { return }
        activeFormatting.append(opened)
    }

    private func processInFrameset(_ token: Token) {
        switch token {
        case let .startTag(name, attributes, _) where name == "frameset":
            let element = PureXML.Model.TreeNode.element("frameset", attributes: modelAttributes(attributes))
            framesetStack.last?.append(element)
            framesetStack.append(element)
        case let .startTag(name, attributes, _) where name == "frame":
            framesetStack.last?.append(PureXML.Model.TreeNode.element("frame", attributes: modelAttributes(attributes)))
        case let .startTag(name, attributes, _) where name == "noframes":
            framesetStack.last?.append(PureXML.Model.TreeNode.element("noframes", attributes: modelAttributes(attributes)))
        case let .endTag(name) where name == "frameset":
            if framesetStack.count > 1 { framesetStack.removeLast() } else { mode = .afterFrameset }
        case let .comment(value):
            framesetStack.last?.append(.comment(value))
        default:
            break
        }
    }

    /// The lowercased tag name of an open element, for case-insensitive matching.
    func tagName(_ node: PureXML.Model.TreeNode) -> String {
        node.name?.localName.lowercased() ?? ""
    }

    /// Tags that close an open `<select>` (the "in select" rule): a nested select,
    /// or an input/keygen/textarea.
    private static let closesSelect: Set<String> = ["select", "input", "keygen", "textarea"]

    /// Table-structural tags that close a select which is inside a table (the "in
    /// select in table" rule).
    private static let closesSelectInTable: Set<String> = ["caption", "table", "tbody", "tfoot", "thead", "tr", "td", "th"]

    /// The open-stack index of a `<select>` that an opening table tag should close
    /// (a select inside a table), or nil when there is none.
    private func selectInTableToClose(for name: String) -> Int? {
        guard Self.closesSelectInTable.contains(name),
              let selectIndex = openBody.lastIndex(where: { tagName($0) == "select" }), selectIndex >= 1,
              openBody[..<selectIndex].contains(where: { tagName($0) == "table" }) else { return nil }
        return selectIndex
    }

    private func bodyOpen(_ name: String, _ attributes: [(String, String)], selfClosing: Bool) {
        if Self.closesSelect.contains(name), let selectIndex = openBody.lastIndex(where: { tagName($0) == "select" }), selectIndex >= 1 {
            openBody.removeLast(openBody.count - selectIndex)
            if name == "select" { return } // a nested select just closes the open one
        }
        if let selectIndex = selectInTableToClose(for: name) {
            openBody.removeLast(openBody.count - selectIndex)
        }
        if let closes = PureXML.HTML.Elements.impliedClose[name] {
            while let top = openBody.last, top !== bodyRoot, closes.contains(tagName(top)) {
                openBody.removeLast()
            }
        }
        bodyEnsureTableContext(for: name)
        let namespace = bodyForeignNamespace(for: name)
        let element = PureXML.Model.TreeNode.element(qualifiedName(name, namespace), attributes: adjustedAttributes(modelAttributes(attributes), namespace: namespace))
        placeElement(element, name: name)
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

    /// Restores SVG attribute names to their canonical camel case.
    private func adjustedAttributes(_ attributes: [Attribute], namespace: String?) -> [Attribute] {
        guard namespace == ForeignNamespace.svg else { return attributes }
        return attributes.map { attribute in
            guard let adjusted = PureXML.HTML.ForeignNames.svgAttributes[attribute.name.localName.lowercased()] else { return attribute }
            return Attribute(adjusted, attribute.value)
        }
    }

    /// The foreign-content namespace for a body element: SVG/MathML on entry, the
    /// nearest open foreign ancestor's, or HTML (nil) inside an integration point.
    private func bodyForeignNamespace(for name: String) -> String? {
        if name == "svg" { return ForeignNamespace.svg }
        if name == "math" { return ForeignNamespace.mathml }
        for node in openBody.reversed() {
            guard let namespace = node.name?.namespaceURI else { continue }
            if Self.svgIntegrationPoints.contains(tagName(node)) { return nil }
            return namespace
        }
        return nil
    }

    /// The SVG HTML integration points: their content is parsed as HTML.
    private static let svgIntegrationPoints: Set<String> = ["foreignobject", "desc", "title"]
}

extension HTMLDocument {
    /// A qualified name carrying its foreign-content namespace, with SVG element
    /// names restored to their canonical camel case.
    private func qualifiedName(_ name: String, _ namespace: String?) -> PureXML.Model.QualifiedName {
        let local = namespace == ForeignNamespace.svg ? (PureXML.HTML.ForeignNames.svgElements[name] ?? name) : name
        return PureXML.Model.QualifiedName(prefix: nil, localName: local, namespaceURI: namespace)
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
