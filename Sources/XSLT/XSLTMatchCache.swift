/// What one match pattern selected: tree-node and attribute identities.
private struct PatternMatches {
    var trees: Set<ObjectIdentifier> = []
    var attributes: Set<PureXML.XSLT.AttributeIdentity> = []
}

extension PureXML.XSLT {
    /// An attribute node's identity: its owner's identity plus its name.
    struct AttributeIdentity: Hashable {
        let owner: ObjectIdentifier
        let name: String
    }

    /// Caches, per transform, the node set each match pattern selects over the
    /// source tree (tree nodes and attribute nodes), so a pattern is compiled
    /// and evaluated once per document rather than once per (node, template)
    /// pair during template selection.
    final class MatchCache {
        private var matched: [String: PatternMatches] = [:]

        /// The identities of the tree nodes `pattern` selects over `root`.
        func nodes(
            matching pattern: String,
            over root: PureXML.Model.TreeNode,
            functions: PureXML.XPath.FunctionTable = .init(),
            namespaces: [String: String] = [:],
        ) -> Set<ObjectIdentifier> {
            compute(pattern, root, functions, namespaces).trees
        }

        /// The identities of the attribute nodes `pattern` selects over `root`.
        func attributes(
            matching pattern: String,
            over root: PureXML.Model.TreeNode,
            functions: PureXML.XPath.FunctionTable = .init(),
            namespaces: [String: String] = [:],
        ) -> Set<AttributeIdentity> {
            compute(pattern, root, functions, namespaces).attributes
        }

        /// Computed and cached on first use; a branch that fails to compile
        /// selects nothing. The function table makes `key()` and `id()`
        /// patterns work; the bindings resolve prefixed name tests by URI.
        private func compute(_ pattern: String, _ root: PureXML.Model.TreeNode, _ functions: PureXML.XPath.FunctionTable, _ namespaces: [String: String]) -> PatternMatches {
            var key = pattern + "\u{1}" + namespaces.sorted(by: { $0.key < $1.key }).map { $0.key + "=" + $0.value }.joined(separator: ";")
            key += "\u{1}\(UInt(bitPattern: ObjectIdentifier(root).hashValue))"

            if let cached = matched[key] { return cached }
            var result = PatternMatches()
            for branch in pattern.split(separator: "|") {
                let trimmed = branch.trimmingXMLWhitespace()
                let path = trimmed.hasPrefix("/") || trimmed.hasPrefix("key(") || trimmed.hasPrefix("id(") ? trimmed : "//" + trimmed
                guard let query = try? PureXML.XPath.Query(path),
                      let value = try? query.value(atNode: .tree(root), position: 1, size: 1, variables: [:], functions: functions, namespaces: namespaces),
                      let selected = value.nodes
                else { continue }
                for node in selected {
                    switch node {
                    case let .tree(tree):
                        result.trees.insert(ObjectIdentifier(tree))
                    case let .attribute(owner, attribute):
                        result.attributes.insert(AttributeIdentity(owner: ObjectIdentifier(owner), name: attribute.name.description))
                    case .namespace:
                        break
                    }
                }
            }
            matched[key] = result
            return result
        }
    }
}
