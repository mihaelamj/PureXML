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
        private let matchCache = MatchCache()
        private let documentCache = PureXML.XSLT.DocumentCache()

        /// The `xsl:message terminate="yes"` text, if one fired during `run()`.
        var terminationMessage: String? {
            termination.message
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
        ) {
            self.parameters = parameters
            self.stylesheet = stylesheet
            self.root = root
            self.documentLoader = documentLoader
            self.stylesheetDocument = stylesheetDocument
            self.unparsedEntityURIs = unparsedEntityURIs
            if !idAttributes.isEmpty {
                documentCache.idAttributes[ObjectIdentifier(root)] = idAttributes
            }
            // One table for all pattern matching: matches() runs per
            // (template, node) during template selection, so a fresh table
            // per call would be allocated millions of times on large inputs.
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
            let context = XSLTContext(node: root, position: 1, size: 1, variables: evaluatedGlobals())
            return .document(applyTemplates(to: [.tree(root)], mode: nil, parameters: [], context).compactMap(Self.nodeOf))
        }

        fileprivate func bestTemplate(for node: PureXML.XPath.Node, mode: String?, below ceiling: Int = .max, atLeast floor: Int = .min) -> Template? {
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
            // Patterns evaluate over the node's own document, so templates
            // match nodes loaded through document() too.
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

        func applyTemplates(
            to nodes: [PureXML.XPath.Node],
            mode: String?,
            parameters: [Binding],
            _ context: XSLTContext,
        ) -> [ResultItem] {
            var items: [ResultItem] = []
            for (offset, xnode) in nodes.enumerated() {
                guard let owner = Self.ownerNode(xnode) else { continue }
                let nodeContext = XSLTContext(
                    node: owner,
                    current: xnode.treeNode == nil ? xnode : nil,
                    position: offset + 1,
                    size: nodes.count,
                    variables: context.variables,
                    mode: mode,
                )
                if let template = bestTemplate(for: xnode, mode: mode) {
                    items += instantiateTemplate(template, nodeContext, passing: parameters, from: context)
                } else {
                    items += builtInRule(xnode, mode: mode, nodeContext)
                }
            }
            return items
        }

        func instantiate(_ body: [Instruction], _ context: XSLTContext) -> [ResultItem] {
            var items: [ResultItem] = []
            var context = context
            for instruction in body {
                if termination.message != nil { break }
                switch instruction {
                case let .variable(name, select, varBody):
                    context.variables[name] = variableValue(select, varBody, context)
                case let .fallback(fallbackBody):
                    items += instantiate(fallbackBody, context)
                default:
                    items += evaluate(instruction, context)
                }
            }
            return items
        }

        func variableValue(_ select: String?, _ body: [Instruction], _ context: XSLTContext) -> PureXML.XPath.Value {
            if let select { return value(select, context) ?? .string("") }
            // XSLT 1.0 11.2: a variable with no select and EMPTY content is the
            // empty string (equivalent to select=""), not a result tree fragment,
            // so boolean() of it is false. Only non-empty content is an RTF.
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
                ),
                namespaces: context.namespaces,
            )
        }

        fileprivate func selectNodes(_ expression: String, _ context: XSLTContext) -> [PureXML.Model.TreeNode] {
            value(expression, context)?.nodes?.compactMap(\.treeNode) ?? []
        }

        /// Like `selectNodes` but keeping attribute and namespace nodes,
        /// which templates apply to as well.
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
            // Raw-output markers do not survive string extraction (16.4:
            // escaping is disabled only for text written directly to the
            // result tree), so a fragment round-trip re-enables escaping.
            // Gated so source text in a stylesheet without
            // disable-output-escaping passes through untouched.
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
            switch node {
            case let .text(value), let .cdata(value): value
            case let .element(element): element.children.reduce(into: "") { $0 += stringValue($1) }
            case let .document(children): children.reduce(into: "") { $0 += stringValue($1) }
            default: ""
            }
        }
    }
}

extension PureXML.XSLT.Transformer {
    fileprivate func evaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem] {
        simpleEvaluate(instruction, context) ?? structuralEvaluate(instruction, context)
    }

    private func simpleEvaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem]? {
        switch instruction {
        case let .literalText(text): [.node(.text(text))]
        case let .valueOf(select, raw):
            [.node(.text(raw ? PureXML.XSLT.RawText.marked(string(select, context)) : string(select, context)))]
        case let .applyTemplates(select, mode, sorts, parameters):
            applyTemplates(
                to: sorted(selectXPathNodes(select ?? "node()", context), sorts, context),
                mode: mode,
                parameters: parameters,
                context,
            )
        case let .forEach(select, sorts, body): forEach(select, sorts, body, context)
        case let .ifInstruction(test, body): boolean(test, context) ? instantiate(body, context) : []
        case let .choose(whens, otherwise): chooseInstruction(whens, otherwise, context)
        case let .copyOf(select): copyOf(select, context)
        case let .callTemplate(name, parameters): callTemplate(name, parameters, context)
        case .variable: []
        default: nil
        }
    }

    // Instantiates an `xsl:message` body as its text; `terminate` records the
    // signal so the transform aborts with it. Produces no result-tree output.

    // Builds a literal result element, rewriting its name and attribute names
    // through any `xsl:namespace-alias` in effect.

    private func structuralEvaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem] {
        switch instruction {
        case .literalElement:
            [literalResult(instruction, context)]
        case .element:
            elementInstruction(instruction, context)
        case let .attribute(nameTemplate, namespaceTemplate, namespaces, body):
            attributeInstruction(nameTemplate, namespaceTemplate, namespaces, body, context)
        case let .copy(useAttributeSets, body):
            copyInstruction(useAttributeSets, body, context)
        case .number:
            [.node(.text(numberInstruction(instruction, context)))]
        case let .comment(body):
            [.node(.comment(Self.text(of: instantiate(body, context))))]
        case let .processingInstruction(name, body):
            [.node(.processingInstruction(target: avt(name, context), data: Self.text(of: instantiate(body, context))))]
        case let .message(terminate, body):
            message(terminate, body, context)
        case .applyImports:
            applyImports(context)
        default:
            []
        }
    }

    /// Re-applies templates to the current node in the current mode, considering
    /// only those below the current template's import precedence, falling back to
    /// the built-in rule when none match.
    private func applyImports(_ context: XSLTContext) -> [ResultItem] {
        if let template = bestTemplate(for: context.focus, mode: context.mode, below: context.importPrecedence, atLeast: context.importRangeLow) {
            return instantiateTemplate(template, context, passing: [], from: context)
        }
        return builtInRule(context.focus, mode: context.mode, context)
    }

    private func callTemplate(_ name: String, _ parameters: [PureXML.XSLT.Binding], _ context: XSLTContext) -> [ResultItem] {
        // XSLT 1.0 section 6: pick the highest import-precedence definition, not the
        // first by position, so an included template outranks a same-name import.
        guard let template = stylesheet.templates.filter({ $0.name == name })
            .max(by: { $0.importPrecedence < $1.importPrecedence }) else { return [] }
        return instantiateTemplate(template, context, passing: parameters, from: context)
    }

    private func copyOf(_ select: String, _ context: XSLTContext) -> [ResultItem] {
        guard let nodes = value(select, context)?.nodes else {
            // A non-node-set result copies as its string value.
            return value(select, context).map { [.node(.text($0.string))] } ?? []
        }
        return nodes.map { xnode in
            switch xnode {
            case let .tree(tree): .node(tree.node)
            case let .attribute(_, attribute): .attribute(attribute)
            case let .namespace(_, prefix, uri):
                .attribute(.init(prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)", uri))
            }
        }
    }

    // MARK: Building elements

    func buildElement(
        name: PureXML.Model.QualifiedName,
        literalAttributes: [PureXML.XSLT.LiteralAttribute],
        useAttributeSets: [String],
        body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> ResultItem {
        // Attribute sets are lowest precedence, then the element's literal
        // attributes, then its xsl:attribute body; a later same-named attribute
        // replaces an earlier one.
        var attributes = attributeSetAttributes(useAttributeSets, context, visiting: [])
        attributes += literalAttributes.map { PureXML.Model.Attribute(name: $0.name, value: avt($0.value, context)) }
        var children: [PureXML.Model.Node] = []
        for item in instantiate(body, context) {
            switch item {
            case let .attribute(attribute):
                // Ignored once content has been added (the XSLT recovery for
                // an attribute created after children).
                if children.isEmpty { attributes.append(attribute) }
            case let .node(node): children.append(node)
            }
        }
        return .node(.element(.init(name: name, attributes: Self.deduplicated(attributes), children: children)))
    }

    /// The attributes contributed by `names` and the attribute sets they include,
    /// lower precedence first, with a `visiting` guard against recursive includes.
    private func attributeSetAttributes(_ names: [String], _ context: XSLTContext, visiting: Set<String>) -> [PureXML.Model.Attribute] {
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
