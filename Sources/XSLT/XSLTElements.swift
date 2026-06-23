extension PureXML.XSLT.Transformer {
    /// Compares strings case-insensitively, with `caseOrder` breaking ties among
    /// strings that differ only in case (the XSLT `case-order` semantics).
    static func caseInsensitiveCompare(_ left: String, _ right: String, _ caseOrder: PureXML.XSLT.CaseOrder) -> Int {
        let leftLower = left.lowercased()
        let rightLower = right.lowercased()
        if leftLower != rightLower { return leftLower < rightLower ? -1 : 1 }
        if left == right { return 0 }
        // Equal apart from case: codepoint order puts uppercase first.
        let upperFirst = left < right
        let leftFirst = caseOrder == .upperFirst ? upperFirst : !upperFirst
        return leftFirst ? -1 : 1
    }

    /// Rewrites a literal name in an `xsl:namespace-alias`ed stylesheet namespace
    /// to its result namespace and prefix; other names pass through unchanged.
    func aliased(_ name: PureXML.Model.QualifiedName) -> PureXML.Model.QualifiedName {
        guard let alias = stylesheet.namespaceAliases[name.namespaceURI ?? ""] else { return name }
        return PureXML.Model.QualifiedName(prefix: alias.prefix, localName: name.localName, namespaceURI: alias.uri)
    }

    /// The attributes with duplicates by name removed, keeping the last (so a
    /// later attribute overrides one from an attribute set or an earlier source).
    static func deduplicated(_ attributes: [PureXML.Model.Attribute]) -> [PureXML.Model.Attribute] {
        var indexByName: [String: Int] = [:]
        var result: [PureXML.Model.Attribute] = []
        for attribute in attributes {
            if let index = indexByName[attribute.name.description] {
                result[index] = attribute
            } else {
                indexByName[attribute.name.description] = result.count
                result.append(attribute)
            }
        }
        return result
    }

    /// The expanded name an xsl:element/xsl:attribute creates (7.1.2/7.1.3):
    /// an explicit namespace attribute wins; otherwise a prefixed name
    /// resolves against the instruction's in-scope stylesheet declarations
    /// (an unprefixed attribute name stays in no namespace).
    func createdName(
        _ nameTemplate: PureXML.XSLT.ValueTemplate,
        _ namespaceTemplate: PureXML.XSLT.ValueTemplate?,
        _ namespaces: [String: String],
        _ context: PureXML.XSLT.XSLTContext,
        isAttribute: Bool,
    ) -> PureXML.Model.QualifiedName {
        let raw = avt(nameTemplate, context)
        var name = PureXML.Model.QualifiedName(raw)
        if let namespaceTemplate {
            let uri = avt(namespaceTemplate, context)
            if !uri.isEmpty {
                return PureXML.Model.QualifiedName(prefix: name.prefix, localName: name.localName, namespaceURI: uri)
            }
            return PureXML.Model.QualifiedName(prefix: nil, localName: name.localName, namespaceURI: nil)
        }
        if let prefix = name.prefix {
            if prefix == "xml" {
                name = PureXML.Model.QualifiedName(prefix: prefix, localName: name.localName, namespaceURI: "http://www.w3.org/XML/1998/namespace")
            } else if let uri = namespaces[prefix] {
                name = PureXML.Model.QualifiedName(prefix: prefix, localName: name.localName, namespaceURI: uri)
            }
        } else if !isAttribute, let defaultURI = namespaces[""], !defaultURI.isEmpty {
            name = PureXML.Model.QualifiedName(prefix: nil, localName: name.localName, namespaceURI: defaultURI)
        }
        return name
    }

    func elementInstruction(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [PureXML.XSLT.ResultItem] {
        guard case let .element(nameTemplate, namespaceTemplate, namespaces, useAttributeSets, body) = instruction else {
            return []
        }
        let raw = avt(nameTemplate, context)
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        if raw.isEmpty || parts.contains(where: \.isEmpty) || parts.count > 2 {
            // An unusable element name: the recovery is to emit the content
            // without the wrapper element.
            return instantiate(body, context).filter { if case .attribute = $0 { false } else { true } }
        }
        let name = createdName(nameTemplate, namespaceTemplate, namespaces, context, isAttribute: false)
        return [buildElement(name: name, literalAttributes: [], useAttributeSets: useAttributeSets, body: body, context)]
    }

    func attributeInstruction(
        _ nameTemplate: PureXML.XSLT.ValueTemplate,
        _ namespaceTemplate: PureXML.XSLT.ValueTemplate?,
        _ namespaces: [String: String],
        _ body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [PureXML.XSLT.ResultItem] {
        let name = createdName(nameTemplate, namespaceTemplate, namespaces, context, isAttribute: true)
        return [.attribute(.init(name: name, value: Self.text(of: instantiate(body, context))))]
    }

    func copyInstruction(_ useAttributeSets: [String], _ body: [PureXML.XSLT.Instruction], _ context: XSLTContext) -> [PureXML.XSLT.ResultItem] {
        // A non-tree current node copies itself: an attribute node yields an
        // attribute result, a namespace node its declaration.
        if let current = context.current {
            switch current {
            case let .attribute(_, attribute):
                return [.attribute(attribute)]
            case let .namespace(_, prefix, uri):
                return [.attribute(.init(prefix.isEmpty ? "xmlns" : "xmlns:" + prefix, uri))]
            case .tree:
                break
            }
        }
        switch context.node.kind {
        case .element:
            let copied = buildElement(
                name: context.node.name ?? .init(""),
                literalAttributes: Self.namespaceDeclarations(inScopeAt: context.node),
                useAttributeSets: useAttributeSets,
                body: body,
                context,
            )
            return [copied]
        case .text, .cdata:
            return [.node(.text(context.node.value))]
        case .comment:
            return [.node(.comment(context.node.value))]
        case .processingInstruction:
            return [.node(.processingInstruction(target: context.node.name?.description ?? "", data: context.node.value))]
        default:
            return instantiate(body, context)
        }
    }
}

extension PureXML.XSLT.Transformer {
    /// The concatenated value of only the text and CDATA node items, ignoring an
    /// element (or other) node together with its content. xsl:comment and
    /// xsl:processing-instruction may contain only text (XSLT 1.0 7.4, 7.6); the
    /// recovery for a created non-text node is to ignore it and its content,
    /// which is not the same as taking the string-value of everything.
    static func textNodesOnly(of items: [PureXML.XSLT.ResultItem]) -> String {
        items.reduce(into: "") { result, item in
            guard case let .node(node) = item else { return }
            switch node {
            case let .text(value), let .cdata(value): result += value
            default: break
            }
        }
    }

    /// The source element's in-scope namespace declarations as literal
    /// xmlns attributes (xsl:copy copies namespace nodes, 7.5); the fixup
    /// pass drops the ones already in scope in the result.
    static func namespaceDeclarations(inScopeAt node: PureXML.Model.TreeNode) -> [PureXML.XSLT.LiteralAttribute] {
        var bindings: [String: String] = [:]
        var current: PureXML.Model.TreeNode? = node
        while let candidate = current {
            for attribute in candidate.attributes {
                if attribute.name.prefix == "xmlns", bindings[attribute.name.localName] == nil {
                    bindings[attribute.name.localName] = attribute.value
                } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns", bindings[""] == nil {
                    bindings[""] = attribute.value
                }
            }
            current = candidate.parent
        }
        return bindings.sorted(by: { $0.key < $1.key }).compactMap { prefix, uri in
            if prefix.isEmpty, uri.isEmpty { return nil }
            let name = prefix.isEmpty ? "xmlns" : "xmlns:" + prefix
            return PureXML.XSLT.LiteralAttribute(name: PureXML.Model.QualifiedName(name), value: [.literal(uri)])
        }
    }

    /// The topmost ancestor of `node` (its document node).
    static func documentRoot(of node: PureXML.Model.TreeNode) -> PureXML.Model.TreeNode {
        var current = node
        while let parent = current.parent {
            current = parent
        }
        return current
    }

    /// `xsl:number`: an explicit `value` expression rounds per the XSLT 1.0
    /// rules; otherwise the level/count/from machinery numbers the context
    /// node, with patterns matched through the transform's match cache.
    func numberInstruction(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> String {
        guard case let .number(spec) = instruction else { return "" }
        let grouping = spec.groupingSeparator.flatMap { separator in
            spec.groupingSize.map { (separator: separator, size: $0) }
        }
        if let valueExpression = spec.value {
            let number = value(valueExpression, context)?.number ?? .nan
            // Outside [1, Int.max] the number renders as a plain XPath
            // number (below one there is nothing to format; above, the Int
            // conversion would trap; the bound is platform-correct, so
            // wasm32's 32-bit Int is honored too).
            guard number.isFinite, number.rounded() >= 1, number.rounded() <= Double(Int.max) else {
                return PureXML.XPath.Value.format(number)
            }
            return XSLTNumbering.format([Int(number.rounded())], spec.format, grouping)
        }
        let numbers = XSLTNumbering.numbers(of: context.node, level: spec.level, count: spec.count, from: spec.from) { node, pattern in
            matches(node, pattern)
        }
        return XSLTNumbering.format(numbers, spec.format, grouping)
    }
}

extension PureXML.XSLT.Transformer {
    /// A literal result element: aliased name and attributes, the copied
    /// 7.1.1 namespace declarations, then the shared element builder.
    func literalResult(_ instruction: PureXML.XSLT.Instruction, _ context: PureXML.XSLT.XSLTContext) -> PureXML.XSLT.ResultItem {
        guard case let .literalElement(name, attributes, namespaces, useAttributeSets, body) = instruction else {
            return .node(.text(""))
        }
        let aliasedAttributes = attributes.map { PureXML.XSLT.LiteralAttribute(name: aliased($0.name), value: $0.value) }
        // The copied namespace nodes (7.1.1) travel as xmlns attributes; the
        // fixup pass reuses them and drops the ones already in scope. An
        // aliased stylesheet namespace declares its result namespace instead.
        var declarations: [PureXML.XSLT.LiteralAttribute] = []
        for (prefix, uri) in namespaces.sorted(by: { $0.key < $1.key }) {
            let alias = stylesheet.namespaceAliases[uri]
            let resolvedPrefix = alias?.prefix ?? (prefix.isEmpty ? nil : prefix)
            let resolvedURI = alias?.uri ?? uri
            let attributeName = resolvedPrefix.map { "xmlns:" + $0 } ?? "xmlns"
            declarations.append(PureXML.XSLT.LiteralAttribute(
                name: PureXML.Model.QualifiedName(attributeName),
                value: [.literal(resolvedURI)],
            ))
        }
        return buildElement(name: aliased(name), literalAttributes: declarations + aliasedAttributes, useAttributeSets: useAttributeSets, body: body, context)
    }
}
