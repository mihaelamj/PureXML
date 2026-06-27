/// The transformer's runtime types are defined in XSLTRuntime.swift (nested in
/// the namespace); these file-private aliases keep them unqualified here.
typealias ResultItem = PureXML.XSLT.ResultItem
typealias XSLTContext = PureXML.XSLT.XSLTContext
private typealias Termination = PureXML.XSLT.Termination
private typealias MatchCache = PureXML.XSLT.MatchCache

extension PureXML.XSLT {
    /// Runs a compiled stylesheet against a source tree, producing a result tree
    /// by the XSLT 1.0 processing model: apply templates from the root, match each
    /// node to the highest-priority template (or the built-in rules), and
    /// instantiate the matched template's sequence constructor.
    struct Transformer {
        let stylesheet: Stylesheet
        let root: PureXML.Model.TreeNode
        let documentLoader: (String) -> String?
        private let keyIndexes = PureXML.XSLT.KeyIndexCache()
        let termination = Termination()
        let recursionGuard = PureXML.XSLT.RecursionGuard()
        /// The deepest template-instantiation nesting allowed before the transform
        /// fails gracefully rather than overflowing the stack. The default clears
        /// the parser's max source depth (so an identity transform of the deepest
        /// permitted source still runs) while staying within an 8 MB stack; raise
        /// it (with a correspondingly larger stack) for deeper legitimate recursion.
        let maxTemplateDepth: Int
        private let matchCache = MatchCache()
        private let documentCache = PureXML.XSLT.DocumentCache()
        let numberingCache = XSLTNumbering.SiblingPositionCache()

        /// The `xsl:message terminate="yes"` text, if one fired during `run()`.
        var terminationMessage: String? {
            termination.message
        }

        /// Whether template recursion hit `maxTemplateDepth` during `run()`, so the
        /// transform was stopped before it could overflow the stack.
        var recursionLimitExceeded: Bool {
            recursionGuard.exceeded
        }

        /// Caller-supplied top-level parameter values, overriding xsl:param defaults.
        let parameters: [String: String]
        /// The stylesheet's own parsed document, returned by `document('')` (12.1).
        let stylesheetDocument: PureXML.Model.Node?
        /// The source DTD's unparsed entities by name to system URI, for `unparsed-entity-uri` (12.4).
        let unparsedEntityURIs: [String: String]

        init(
            stylesheet: Stylesheet,
            root: PureXML.Model.TreeNode,
            documentLoader: @escaping (String) -> String? = { _ in nil },
            idAttributes: [String: Set<String>] = [:],
            parameters: [String: String] = [:],
            stylesheetDocument: PureXML.Model.Node? = nil,
            unparsedEntityURIs: [String: String] = [:],
            baseURI: String = "",
            maxTemplateDepth: Int = PureXML.XSLT.defaultMaxTemplateDepth,
        ) {
            self.parameters = parameters
            self.maxTemplateDepth = maxTemplateDepth
            self.stylesheet = stylesheet
            self.root = root
            self.documentLoader = documentLoader
            self.stylesheetDocument = stylesheetDocument
            self.unparsedEntityURIs = unparsedEntityURIs
            if !idAttributes.isEmpty {
                documentCache.idAttributes[ObjectIdentifier(root)] = idAttributes
            }
            documentCache.registerSelfDocument(stylesheetDocument, at: baseURI)
            // One table for all pattern matching: matches() runs per (template,
            // node), so a fresh table per call would allocate millions of times.
            let caches = keyIndexes
            patternTable = PureXML.XSLT.Library.table(
                current: .tree(root),
                keys: { documentRoot in
                    let identity = ObjectIdentifier(documentRoot)
                    if let cached = caches.indexes[identity] { return cached }
                    let built = PureXML.XSLT.Library.buildKeyIndex(stylesheet: stylesheet, root: documentRoot)
                    caches.indexes[identity] = built
                    return built
                },
                loader: documentLoader,
                decimalFormats: stylesheet.decimalFormats,
                documents: documentCache,
                selfDocument: stylesheetDocument,
                unparsedEntities: unparsedEntityURIs,
            )
        }

        /// The key index for `documentRoot`, built on first use (keys apply
        /// per document: the source and each document() load have their own).
        private func keyIndex(for documentRoot: PureXML.Model.TreeNode) -> PureXML.XSLT.KeyIndex {
            let identity = ObjectIdentifier(documentRoot)
            if let cached = keyIndexes.indexes[identity] { return cached }
            let built = PureXML.XSLT.Library.buildKeyIndex(stylesheet: stylesheet, root: documentRoot)
            keyIndexes.indexes[identity] = built
            return built
        }

        func run() -> PureXML.Model.Node {
            let globals = evaluatedGlobals()
            matchCache.globalVariables = globals // pattern predicates see globals (5.2)
            let context = XSLTContext(node: root, position: 1, size: 1, variables: globals)
            return .document(applyTemplates(to: [.tree(root)], mode: nil, parameters: [], context).compactMap(Self.nodeOf))
        }

        func bestTemplate(for node: PureXML.XPath.Node, mode: String?, below ceiling: Int = .max, atLeast floor: Int = .min) -> Template? {
            stylesheet.templates.enumerated()
                .filter { entry in
                    entry.element.mode == mode && entry.element.importPrecedence < ceiling
                        && entry.element.importPrecedence >= floor
                        && (entry.element.match.map { matches(node, $0, entry.element.namespaces) } ?? false)
                }
                .max { lhs, rhs in
                    (lhs.element.importPrecedence, lhs.element.priority, lhs.offset)
                        < (rhs.element.importPrecedence, rhs.element.priority, rhs.offset)
                }?
                .element
        }

        func matches(_ node: PureXML.Model.TreeNode, _ pattern: String, _ namespaces: [String: String] = [:]) -> Bool {
            let documentRoot = Self.documentRoot(of: node)
            return matchCache.nodes(matching: pattern, over: documentRoot, functions: patternFunctions(), namespaces: namespaces).contains(ObjectIdentifier(node))
        }

        /// Pattern membership for any XPath node kind.
        func matches(_ node: PureXML.XPath.Node, _ pattern: String, _ namespaces: [String: String] = [:]) -> Bool {
            switch node {
            case let .tree(tree):
                matches(tree, pattern, namespaces)
            case let .attribute(owner, attribute):
                matchCache.attributes(matching: pattern, over: Self.documentRoot(of: owner), functions: patternFunctions(), namespaces: namespaces)
                    .contains(PureXML.XSLT.AttributeIdentity(owner: ObjectIdentifier(owner), name: attribute.name.description))
            case .namespace:
                false
            }
        }

        /// The function table match patterns evaluate with (`key()`/`id()`
        /// patterns), rooted at the document and built once in init.
        private let patternTable: PureXML.XPath.FunctionTable

        private func patternFunctions() -> PureXML.XPath.FunctionTable {
            patternTable
        }

        func variableValue(_ select: String?, _ body: [Instruction], _ context: XSLTContext) -> PureXML.XPath.Value {
            if let select { return value(select, context) ?? .string("") }
            // XSLT 1.0 11.2: a variable with no select and empty content is the
            // empty string, not an RTF (so boolean() is false); only content is.
            if body.isEmpty { return .string("") }
            // A body variable is a result-tree fragment: a queryable document node.
            let children = instantiate(body, context).compactMap(Self.nodeOf).map(PureXML.Model.TreeNode.init)
            return .nodeSet([.tree(PureXML.Model.TreeNode.document(children: children))])
        }

        func value(_ expression: String, _ context: XSLTContext) -> PureXML.XPath.Value? {
            guard let query = try? PureXML.XPath.Query(expression) else { return nil }
            return try? query.value(
                atNode: context.focus,
                position: context.position,
                size: context.size,
                variables: context.variables,
                functions: PureXML.XSLT.Library.table(
                    current: context.focus,
                    keys: { keyIndex(for: $0) },
                    loader: documentLoader,
                    decimalFormats: stylesheet.decimalFormats,
                    documents: documentCache,
                    selfDocument: stylesheetDocument,
                    unparsedEntities: unparsedEntityURIs,
                    baseURI: context.baseURI,
                ),
                namespaces: context.namespaces,
            )
        }

        /// Selects the nodes an expression yields, keeping attribute and namespace
        /// nodes, which templates apply to as well.
        func selectXPathNodes(_ expression: String, _ context: XSLTContext) -> [PureXML.XPath.Node] {
            value(expression, context)?.nodes ?? []
        }

        /// The element a context is built around for `xnode`: the node itself
        /// when it is a tree node, otherwise its owner element.
        static func ownerNode(_ xnode: PureXML.XPath.Node) -> PureXML.Model.TreeNode? {
            switch xnode {
            case let .tree(node): node
            case let .attribute(owner, _), let .namespace(owner, _, _): owner
            }
        }

        func string(_ expression: String, _ context: XSLTContext) -> String {
            // Raw-output markers do not survive string extraction (16.4: escaping is disabled only for text written
            // directly to the result tree), so a fragment round-trip re-enables escaping. Gated so source text in a
            // stylesheet without disable-output-escaping passes through untouched.
            let extracted = value(expression, context)?.string ?? ""
            return stylesheet.usesRawText ? PureXML.XSLT.RawText.stripped(extracted) : extracted
        }

        func boolean(_ expression: String, _ context: XSLTContext) -> Bool {
            value(expression, context)?.boolean ?? false
        }

        fileprivate static func nodeOf(_ item: ResultItem) -> PureXML.Model.Node? {
            if case let .node(node) = item { return node }
            return nil
        }

        static func text(of items: [ResultItem]) -> String {
            items.reduce(into: "") { result, item in
                if case let .node(node) = item { result += Self.stringValue(node) }
            }
        }

        private static func stringValue(_ node: PureXML.Model.Node) -> String {
            // Iterative pre-order walk so a deeply-nested result tree does not
            // overflow the stack; only text and CDATA contribute.
            var result = ""
            var stack: [PureXML.Model.Node] = [node]
            while let current = stack.popLast() {
                switch current {
                case let .text(value), let .cdata(value):
                    result += value
                case let .element(element):
                    stack.append(contentsOf: element.children.reversed())
                case let .document(children):
                    stack.append(contentsOf: children.reversed())
                default:
                    break
                }
            }
            return result
        }
    }
}

extension PureXML.XSLT.Transformer {
    /// The attributes contributed by `names` and the attribute sets they include,
    /// lower precedence first, with a `visiting` guard against recursive includes.
    func attributeSetAttributes(_ names: [String], _ context: XSLTContext, visiting: Set<String>) -> [PureXML.Model.Attribute] {
        var result: [PureXML.Model.Attribute] = []
        for name in names where !visiting.contains(name) {
            for definition in stylesheet.attributeSets[name] ?? [] {
                result += attributeSetAttributes(definition.use, context, visiting: visiting.union([name]))
                for item in instantiate(definition.attributes, context) {
                    if case let .attribute(attribute) = item { result.append(attribute) }
                }
            }
        }
        return result
    }

    func avt(_ template: PureXML.XSLT.ValueTemplate, _ context: XSLTContext) -> String {
        template.reduce(into: "") { result, part in
            switch part {
            case let .literal(text): result += text
            case let .expression(expression): result += string(expression, context)
            }
        }
    }
}
