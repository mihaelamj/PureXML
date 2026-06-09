public extension PureXML.XSLT {
    /// Transforms `source` with `stylesheet`, returning the serialized result.
    /// `documentLoader` resolves the URI argument of the `document()` function to
    /// source text; it returns `nil` (the default) when external documents are
    /// not available, which keeps `document()` from reaching the filesystem or
    /// network by default.
    static func transform(
        stylesheet: String,
        source: String,
        options: PureXML.Emitting.Options = .compact,
        documentLoader: @escaping (String) -> String? = { _ in nil },
    ) throws -> String {
        let sheet = try XSLTParser.parse(stylesheet, loader: documentLoader)
        let root = try PureXML.parseTree(source)
        Whitespace.strip(root, stylesheet: sheet)
        let transformer = Transformer(stylesheet: sheet, root: root, documentLoader: documentLoader)
        let result = transformer.run()
        if let message = transformer.terminationMessage { throw XSLTError.terminated(message) }
        if sheet.output.method == "text" { return textValue(of: result) }
        let body: String
        if sheet.output.method == "html" {
            body = PureXML.HTML.serialize(result)
        } else {
            let prepared = withCDATASections(result, sheet.output.cdataSectionElements)
            body = PureXML.serialize(prepared, options: options.applying(sheet.output))
        }
        return doctype(for: result, sheet.output) + body
    }

    /// Returns `node` with the text children of any element named in `names`
    /// replaced by CDATA nodes, so the serializer emits them as CDATA sections.
    private static func withCDATASections(_ node: PureXML.Model.Node, _ names: Set<String>) -> PureXML.Model.Node {
        guard !names.isEmpty else { return node }
        switch node {
        case let .document(children):
            return .document(children.map { withCDATASections($0, names) })
        case let .element(element):
            let wrap = names.contains(element.name.localName) || names.contains(element.name.description)
            let children = element.children.map { child -> PureXML.Model.Node in
                if wrap, case let .text(value) = child { return .cdata(value) }
                return withCDATASections(child, names)
            }
            return .element(.init(name: element.name, attributes: element.attributes, children: children))
        default:
            return node
        }
    }

    /// The `<!DOCTYPE …>` prologue for the result's root element when the output
    /// declares `doctype-system` (optionally with `doctype-public`), else empty.
    private static func doctype(for result: PureXML.Model.Node, _ output: Output) -> String {
        guard let system = output.doctypeSystem, let name = rootName(of: result) else { return "" }
        let external = output.doctypePublic.map { "PUBLIC \"\($0)\" \"\(system)\"" } ?? "SYSTEM \"\(system)\""
        return "<!DOCTYPE \(name) \(external)>\n"
    }

    private static func rootName(of node: PureXML.Model.Node) -> String? {
        switch node {
        case let .element(element): element.name.description
        case let .document(children): children.compactMap(\.element).first?.name.description
        default: nil
        }
    }

    /// Transforms `source` with `stylesheet`, returning the result tree.
    static func transformToNode(
        stylesheet: String,
        source: String,
        documentLoader: @escaping (String) -> String? = { _ in nil },
    ) throws -> PureXML.Model.Node {
        let sheet = try XSLTParser.parse(stylesheet, loader: documentLoader)
        let root = try PureXML.parseTree(source)
        Whitespace.strip(root, stylesheet: sheet)
        let transformer = Transformer(stylesheet: sheet, root: root, documentLoader: documentLoader)
        let result = transformer.run()
        if let message = transformer.terminationMessage { throw XSLTError.terminated(message) }
        return result
    }

    /// The concatenated text content of a result tree, for the `text` output
    /// method: character data only, with markup, comments, and PIs dropped.
    private static func textValue(of node: PureXML.Model.Node) -> String {
        switch node {
        case let .text(value), let .cdata(value): value
        case let .document(children): children.map(textValue).joined()
        case let .element(element): element.children.map(textValue).joined()
        case .comment, .processingInstruction: ""
        }
    }
}
