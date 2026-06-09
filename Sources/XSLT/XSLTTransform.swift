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
        if sheet.output.method == "html" { return PureXML.HTML.serialize(result) }
        return PureXML.serialize(result, options: options.applying(sheet.output))
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
