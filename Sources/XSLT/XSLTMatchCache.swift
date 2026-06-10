extension PureXML.XSLT {
    /// Caches, per transform, the node set each match pattern selects over the
    /// source tree, so a pattern is compiled and evaluated once per document
    /// rather than once per (node, template) pair during template selection.
    final class MatchCache {
        private var matched: [String: Set<ObjectIdentifier>] = [:]

        /// The identities of the nodes `pattern` selects over `root`, computed and
        /// cached on first use. A branch that fails to compile selects nothing.
        func nodes(matching pattern: String, over root: PureXML.Model.TreeNode) -> Set<ObjectIdentifier> {
            if let cached = matched[pattern] { return cached }
            var result: Set<ObjectIdentifier> = []
            for branch in pattern.split(separator: "|") {
                let trimmed = branch.trimmingXMLWhitespace()
                let path = trimmed.hasPrefix("/") ? trimmed : "//" + trimmed
                if let query = try? PureXML.XPath.Query(path) {
                    for node in query.nodes(over: root) {
                        result.insert(ObjectIdentifier(node))
                    }
                }
            }
            matched[pattern] = result
            return result
        }
    }
}
