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
    static func expandedMode(_ node: XSLTTree) -> String? {
        guard let mode = XSLTNode.attribute(node, "mode") else { return nil }
        guard let colon = mode.firstIndex(of: ":") else { return mode }
        let prefix = String(mode[..<colon])
        let local = String(mode[mode.index(after: colon)...])
        guard let uri = resolvePrefix(prefix, at: node) else { return mode }
        return "{\(uri)}\(local)"
    }

    /// A variable or parameter `name` as an expanded name `{uri}local` when it
    /// carries a prefix, or the bare name when unprefixed. A variable is named by
    /// expanded QName (XSLT 1.0 11.1), so two prefixes bound to one namespace name
    /// the same variable; the XPath evaluator falls back to the same expansion on
    /// a reference, so only a prefixed name changes and unprefixed names are kept.
    static func expandedDeclaredName(_ node: XSLTTree) -> String {
        let raw = XSLTNode.attribute(node, "name") ?? ""
        guard let colon = raw.firstIndex(of: ":") else { return raw }
        let prefix = String(raw[..<colon])
        let local = String(raw[raw.index(after: colon)...])
        guard let uri = resolvePrefix(prefix, at: node) else { return raw }
        return "{\(uri)}\(local)"
    }

    static func addAttributeSet(_ child: XSLTTree, into parts: inout Parts) {
        guard let name = XSLTNode.attribute(child, "name") else { return }
        // Same-name attribute sets merge (7.1.4) as ordered definitions:
        // each expands its used sets before its own attributes, and a later
        // definition's attributes override earlier same-named ones.
        let addition = PureXML.XSLT.AttributeSet(attributes: body(child), use: useAttributeSets(child))
        parts.attributeSets[name, default: []].append(addition)
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
