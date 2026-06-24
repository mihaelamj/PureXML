/// Top-level declaration helpers for ``XSLTParser``, kept in a separate file so
/// the parser enum stays within the type-body and file length budgets.
extension PureXML.XSLT.XSLTParser {
    /// Records an `xsl:namespace-alias`: the namespace bound to `stylesheet-prefix`
    /// is rewritten to the one bound to `result-prefix` (with that prefix) on output.
    static func addNamespaceAlias(_ child: XSLTTree, into parts: inout Parts) {
        let stylePrefix = XSLTNode.attribute(child, "stylesheet-prefix") ?? "#default"
        let resultPrefix = XSLTNode.attribute(child, "result-prefix") ?? "#default"
        let key = resolvePrefix(stylePrefix, at: child) ?? ""
        parts.namespaceAliases[key] = PureXML.XSLT.NamespaceAlias(
            uri: resolvePrefix(resultPrefix, at: child),
            prefix: resultPrefix == "#default" ? nil : resultPrefix,
        )
    }

    /// Resolves a namespace prefix (or `#default`) to its URI from the `xmlns`
    /// declarations in scope at `node`, walking up to the stylesheet element.
    static func resolvePrefix(_ prefix: String, at node: XSLTTree) -> String? {
        var current: XSLTTree? = node
        while let element = current {
            for attribute in element.attributes {
                let isDefault = prefix == "#default" && attribute.name.prefix == nil && attribute.name.localName == "xmlns"
                let isPrefixed = attribute.name.prefix == "xmlns" && attribute.name.localName == prefix
                if isDefault || isPrefixed { return attribute.value }
            }
            current = element.parent
        }
        return nil
    }

    /// A `mode` attribute as expanded name `{uri}local` (bare local when
    /// unprefixed): a mode is compared by expanded name (XSLT 1.0 5.7), so two
    /// prefixes bound to one namespace are the same mode. nil when absent.
    /// A QName resolved to expanded form `{uri}local`, or the bare name when it
    /// is unprefixed (the null namespace) or its prefix is unbound at `node`.
    /// XSLT 1.0 compares mode, variable, template, key, attribute-set, and
    /// decimal-format names by expanded name, so two prefixes bound to the same
    /// namespace name the same thing.
    static func expandedQName(_ raw: String, at node: XSLTTree) -> String {
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        let prefix = String(raw[..<colon])
        let local = String(raw[raw.index(after: colon)...])
        guard let uri = resolvePrefix(prefix, at: node) else { return raw }
        return "{\(uri)}\(local)"
    }

    static func expandedMode(_ node: XSLTTree) -> String? {
        XSLTNode.attribute(node, "mode").map { expandedQName($0, at: node) }
    }

    /// A strip-space/preserve-space NameTest resolved to namespace form: `*` and
    /// an unprefixed name (the null namespace) stay as is, `prefix:*` becomes
    /// `{uri}*`, and `prefix:local` becomes `{uri}local` (XSLT 1.0 3.4).
    static func expandedSpecifier(_ token: String, at node: XSLTTree) -> String {
        guard let colon = token.firstIndex(of: ":") else { return token }
        let prefix = String(token[..<colon])
        let local = String(token[token.index(after: colon)...])
        guard let uri = resolvePrefix(prefix, at: node) else { return token }
        return "{\(uri)}\(local)"
    }

    /// A variable or parameter `name` as an expanded name `{uri}local` when it
    /// carries a prefix, or the bare name when unprefixed. A variable is named by
    /// expanded QName (XSLT 1.0 11.1), so two prefixes bound to one namespace name
    /// the same variable; the XPath evaluator falls back to the same expansion on
    /// a reference, so only a prefixed name changes and unprefixed names are kept.
    static func expandedDeclaredName(_ node: XSLTTree) -> String {
        expandedQName(XSLTNode.attribute(node, "name") ?? "", at: node)
    }

    static func addAttributeSet(_ child: XSLTTree, into parts: inout Parts) {
        guard XSLTNode.attribute(child, "name") != nil else { return }
        // Same-name attribute sets merge (7.1.4) as ordered definitions:
        // each expands its used sets before its own attributes, and a later
        // definition's attributes override earlier same-named ones. The name is
        // keyed by expanded QName so use-attribute-sets resolves it identically.
        let addition = PureXML.XSLT.AttributeSet(attributes: body(child), use: useAttributeSets(child))
        parts.attributeSets[expandedDeclaredName(child), default: []].append(addition)
    }

    /// Reads an `xsl:decimal-format`'s symbol overrides; each unset attribute
    /// keeps the XSLT standard default.
    static func decimalFormat(_ node: XSLTTree) -> PureXML.XSLT.DecimalFormat {
        var format = PureXML.XSLT.DecimalFormat()
        func char(_ name: String, _ keyPath: WritableKeyPath<PureXML.XSLT.DecimalFormat, Character>) {
            if let value = XSLTNode.attribute(node, name)?.first { format[keyPath: keyPath] = value }
        }
        char("decimal-separator", \.decimalSeparator)
        char("grouping-separator", \.groupingSeparator)
        char("percent", \.percent)
        char("per-mille", \.perMille)
        char("zero-digit", \.zeroDigit)
        char("digit", \.digit)
        char("pattern-separator", \.patternSeparator)
        char("minus-sign", \.minusSign)
        if let infinity = XSLTNode.attribute(node, "infinity") { format.infinity = infinity }
        if let notANumber = XSLTNode.attribute(node, "NaN") { format.notANumber = notANumber }
        return format
    }
}
