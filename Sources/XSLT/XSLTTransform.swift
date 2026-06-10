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
        baseURI: String = "",
    ) throws -> String {
        let documentLoader = resolvingLoader(documentLoader, baseURI: baseURI)
        let sheet = try XSLTParser.parse(stylesheet, loader: documentLoader)
        let root = try PureXML.parseTree(source)
        Whitespace.strip(root, stylesheet: sheet)
        let transformer = Transformer(stylesheet: sheet, root: root, documentLoader: documentLoader)
        let result = transformer.run()
        if let message = transformer.terminationMessage { throw XSLTError.terminated(message) }
        let method = sheet.output.method ?? defaultMethod(for: result)
        if method == "text" { return RawText.resolve(textValue(of: result)) }
        let body: String
        if method == "html" {
            body = PureXML.HTML.serialize(withContentTypeMeta(result, encoding: sheet.output.encoding ?? "UTF-8"))
        } else {
            let fixed = XSLTNamespaceFixup.apply(result)
            let prepared = withCDATASections(fixed, sheet.output.cdataSectionElements)
            var emitOptions = options.applying(sheet.output)
            if sheet.output.omitXMLDeclaration == nil { emitOptions.includeXMLDeclaration = true }
            body = PureXML.serialize(prepared, options: emitOptions)
        }
        return doctype(for: result, sheet.output) + RawText.resolve(body)
    }

    /// The default output method (16.1): html when the first element of the
    /// result is named html in any case combination (with only whitespace
    /// text before it), otherwise xml.
    private static func defaultMethod(for node: PureXML.Model.Node) -> String {
        guard case let .document(children) = node else { return "xml" }
        for child in children {
            switch child {
            case let .element(element):
                let isHTML = element.name.description.lowercased() == "html" && (element.name.namespaceURI ?? "").isEmpty
                return isHTML ? "html" : "xml"
            case let .text(value) where value.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }:
                continue
            default:
                return "xml"
            }
        }
        return "xml"
    }

    /// Returns `node` with a `META http-equiv="Content-Type"` element
    /// prepended to the children of the first `head` element (16.2: the html
    /// output method should add a meta element giving the encoding).
    private static func withContentTypeMeta(_ node: PureXML.Model.Node, encoding: String) -> PureXML.Model.Node {
        switch node {
        case let .document(children):
            return .document(children.map { withContentTypeMeta($0, encoding: encoding) })
        case let .element(element):
            var children = element.children.map { withContentTypeMeta($0, encoding: encoding) }
            let needsMeta = element.name.localName.lowercased() == "head"
                && !children.contains(where: { isContentTypeMeta($0) })
            if needsMeta {
                let meta = PureXML.Model.Element(
                    name: .init("META"),
                    attributes: [
                        .init("http-equiv", "Content-Type"),
                        .init("content", "text/html; charset=\(encoding)"),
                    ],
                    children: [],
                )
                children.insert(.element(meta), at: 0)
            }
            return .element(.init(name: element.name, attributes: element.attributes, children: children))
        default:
            return node
        }
    }

    private static func isContentTypeMeta(_ node: PureXML.Model.Node) -> Bool {
        guard case let .element(element) = node, element.name.localName.lowercased() == "meta" else { return false }
        return element.attributes.contains { $0.name.localName.lowercased() == "http-equiv" }
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

    /// Wraps `loader` so a relative URI (from `document()`, `xsl:include`, or
    /// `xsl:import`) is resolved against `baseURI` before loading. An empty base
    /// leaves URIs as written.
    private static func resolvingLoader(_ loader: @escaping (String) -> String?, baseURI: String) -> (String) -> String? {
        guard !baseURI.isEmpty else { return loader }
        return { reference in loader(PureXML.XInclude.URIReference.resolve(reference, against: baseURI)) }
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
        baseURI: String = "",
    ) throws -> PureXML.Model.Node {
        let documentLoader = resolvingLoader(documentLoader, baseURI: baseURI)
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
