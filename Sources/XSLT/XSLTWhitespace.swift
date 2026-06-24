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

        /// Whether an element has its whitespace stripped. Specifiers are matched
        /// by namespace in order of specificity (an expanded `{uri}local` name
        /// over a namespace wildcard `{uri}*` over `*`), and `preserve-space`
        /// beats `strip-space` on a tie (XSLT 1.0 3.4).
        private static func shouldStrip(_ node: PureXML.Model.TreeNode, _ stripSet: Set<String>, _ preserveSet: Set<String>) -> Bool {
            let uri = node.name?.namespaceURI ?? ""
            let local = node.name?.localName ?? ""
            let expanded = uri.isEmpty ? local : "{\(uri)}\(local)"
            let namespaceWildcard = uri.isEmpty ? nil : "{\(uri)}*"
            for test in [expanded, namespaceWildcard, "*"].compactMap(\.self) {
                if preserveSet.contains(test) { return false }
                if stripSet.contains(test) { return true }
            }
            return false
        }

        private static func xmlSpace(_ node: PureXML.Model.TreeNode) -> String? {
            node.attributes.first { $0.name.localName == "space" && $0.name.prefix == "xml" }?.value
        }

        private static func isWhitespace(_ value: String) -> Bool {
            // XML whitespace only: NBSP and other Unicode spaces are content.
            value.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        }
    }
}
