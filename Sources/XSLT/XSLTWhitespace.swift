extension PureXML.XSLT {
    /// Applies a stylesheet's `xsl:strip-space` / `xsl:preserve-space` to the
    /// source tree, removing whitespace-only text nodes from stripped elements
    /// before transformation. `xml:space="preserve"` on an element or an ancestor
    /// (until an `xml:space="default"` resets it) forces preservation regardless
    /// of `strip-space`, per the XSLT 1.0 whitespace-stripping rules. CDATA is
    /// significant and never stripped.
    enum Whitespace {
        static func strip(_ root: PureXML.Model.TreeNode, stylesheet: Stylesheet) {
            guard !stylesheet.stripSpace.isEmpty else { return }
            strip(root, stylesheet.stripSpace, stylesheet.preserveSpace, inScopePreserve: false)
        }

        private static func strip(
            _ node: PureXML.Model.TreeNode,
            _ stripSet: Set<String>,
            _ preserveSet: Set<String>,
            inScopePreserve: Bool,
        ) {
            let preserveHere = xmlSpace(node).map { $0 == "preserve" } ?? inScopePreserve
            if node.kind == .element, !preserveHere, shouldStrip(node, stripSet, preserveSet) {
                for child in node.children where child.kind == .text && isWhitespace(child.value) {
                    node.removeChild(child)
                }
            }
            for child in node.children {
                strip(child, stripSet, preserveSet, inScopePreserve: preserveHere)
            }
        }

        /// Whether an element with this name has its whitespace stripped: a name
        /// test wins over `*`, and `preserve-space` beats `strip-space` on a tie.
        private static func shouldStrip(_ node: PureXML.Model.TreeNode, _ stripSet: Set<String>, _ preserveSet: Set<String>) -> Bool {
            let names = [node.name?.localName, node.name?.description].compactMap(\.self)
            if names.contains(where: preserveSet.contains) { return false }
            if names.contains(where: stripSet.contains) { return true }
            if preserveSet.contains("*") { return false }
            return stripSet.contains("*")
        }

        private static func xmlSpace(_ node: PureXML.Model.TreeNode) -> String? {
            node.attributes.first { $0.name.localName == "space" && $0.name.prefix == "xml" }?.value
        }

        private static func isWhitespace(_ value: String) -> Bool {
            value.allSatisfy(\.isWhitespace)
        }
    }
}
