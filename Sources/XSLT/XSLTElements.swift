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
    /// to its result namespace, keeping the literal prefix; other names pass
    /// through unchanged.
    func aliased(_ name: PureXML.Model.QualifiedName) -> PureXML.Model.QualifiedName {
        guard let alias = stylesheet.namespaceAliases[name.namespaceURI ?? ""] else { return name }
        // The literal prefix is kept and only its namespace URI is remapped (XSLT
        // 1.0 7.1.1: the result namespace node keeps the stylesheet prefix); the
        // result-prefix only selects the replacement namespace, it is not adopted.
        return PureXML.Model.QualifiedName(prefix: name.prefix, localName: name.localName, namespaceURI: alias.uri)
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
        let hasExplicitNamespace = (namespaceTemplate.map { !avt($0, context).isEmpty }) ?? false
        let prefix = parts.count == 2 ? String(parts[0]) : nil
        // A prefix not bound to a namespace (and no explicit namespace attribute
        // supplies one) makes the QName unusable, as does a non-NCName part.
        let undeclaredPrefix = !hasExplicitNamespace && (prefix.map { $0 != "xml" && namespaces[$0] == nil } ?? false)
        let unusableName = raw.isEmpty || parts.contains(where: \.isEmpty) || parts.count > 2
            || !parts.allSatisfy { PureXML.Parsing.XMLCharacter.isValidName(String($0)) } || undeclaredPrefix
        if unusableName {
            // The recovery (7.1.2, element-name-not-QName) emits the content
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
        // xsl:attribute content that creates a non-text node ignores it with its
        // content (XSLT 1.0 errata E27), like xsl:comment/processing-instruction.
        return [.attribute(.init(name: name, value: escapedTextValue(of: instantiate(body, context))))]
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
        case .document:
            // Copying the root node produces no element of its own, but xsl:copy
            // may carry use-attribute-sets (7.5); those attributes have no copied
            // element to attach to, so they join the enclosing result element,
            // ahead of the copied content.
            let setAttributes = attributeSetAttributes(useAttributeSets, context, visiting: []).map(PureXML.XSLT.ResultItem.attribute)
            return setAttributes + instantiate(body, context)
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

    /// The text-node content of `items` as the string value of an attribute,
    /// comment, or processing-instruction node, with disable-output-escaping
    /// ignored (XSLT 1.0 16.4: disabling escaping for a value used as something
    /// other than a text node is an error; the recovery is to ignore it). The
    /// raw markers are only stripped when the stylesheet uses the feature, so a
    /// private-use character in ordinary data is never removed.
    func escapedTextValue(of items: [PureXML.XSLT.ResultItem]) -> String {
        let text = Self.textNodesOnly(of: items)
        return stylesheet.usesRawText ? PureXML.XSLT.RawText.stripped(text) : text
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

    /// A copied tree node for `xsl:copy-of`. For an element it carries the
    /// element's full set of in-scope namespace nodes (XSLT 1.0 11.3: copying a
    /// node copies its namespace nodes), so a declaration inherited from an
    /// ancestor of the copied element is added alongside the element's own; the
    /// serializer's namespace fixup later drops any already in the result scope.
    static func withInScopeNamespaces(_ tree: PureXML.Model.TreeNode) -> PureXML.Model.Node {
        guard case let .element(element) = tree.node else { return tree.node }
        let declared = Set(element.attributes
            .filter { $0.name.prefix == "xmlns" || ($0.name.prefix == nil && $0.name.localName == "xmlns") }
            .map(\.name.description))
        let inherited = namespaceDeclarations(inScopeAt: tree).compactMap { decl -> PureXML.Model.Attribute? in
            guard !declared.contains(decl.name.description), case let .literal(uri) = decl.value.first else { return nil }
            return PureXML.Model.Attribute(name: decl.name, value: uri)
        }
        return .element(.init(name: element.name, attributes: element.attributes + inherited, children: element.children))
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
        let format = avt(spec.format, context)
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
            return XSLTNumbering.format([Int(number.rounded())], format, grouping)
        }
        let numbers = XSLTNumbering.numbers(of: context.node, level: spec.level, count: spec.count, from: spec.from) { node, pattern in
            matches(node, pattern)
        }
        return XSLTNumbering.format(numbers, format, grouping)
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
            // Keep the literal prefix; an alias only remaps its namespace URI.
            let resolvedPrefix = prefix.isEmpty ? nil : prefix
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
