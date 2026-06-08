extension PureXML.Schema {
    /// Validates XSD identity constraints (`unique`, `key`, `keyref`) over an
    /// instance document. Each constraint is evaluated at every element whose
    /// name carries it: the selector XPath chooses target nodes relative to that
    /// element, and the field XPaths form each target's value tuple. `key` and
    /// `unique` require distinct tuples; `keyref` requires each tuple to match a
    /// key or unique of the named constraint visible in an enclosing scope.
    struct IdentityValidator {
        /// The constraints declared for each element local name.
        let constraints: [String: [IdentityConstraint]]

        func validate(_ root: PureXML.Model.TreeNode) -> [PureXML.Validation.ValidationError] {
            guard !constraints.isEmpty else { return [] }
            var issues: [PureXML.Validation.ValidationError] = []
            walk(root, scopes: [], into: &issues)
            return issues
        }

        private func walk(
            _ node: PureXML.Model.TreeNode,
            scopes: [[String: [[String?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            var frame: [String: [[String?]]] = [:]
            let declared = node.name.flatMap { constraints[$0.localName] } ?? []
            // Collect key and unique tuples first so a keyref on the same element
            // can resolve against them.
            for constraint in declared {
                collect(constraint, at: node, frame: &frame, into: &issues)
            }
            let visible = scopes + [frame]
            for constraint in declared {
                if case let .keyref(refer) = constraint.kind {
                    checkKeyref(constraint, refer: refer, at: node, scopes: visible, into: &issues)
                }
            }
            for child in node.children where child.kind == .element {
                walk(child, scopes: visible, into: &issues)
            }
        }

        private func isNonRef(_ constraint: IdentityConstraint) -> Bool {
            if case .keyref = constraint.kind { return false }
            return true
        }

        private func collect(
            _ constraint: IdentityConstraint,
            at node: PureXML.Model.TreeNode,
            frame: inout [String: [[String?]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            guard isNonRef(constraint) else { return }
            var tuples: [[String?]] = []
            var seen: [[String?]] = []
            for target in select(constraint.selector, at: node) {
                let tuple = fieldTuple(constraint.fields, at: target)
                if constraint.kind == .key, tuple.contains(where: { $0 == nil }) {
                    issues.append(.init(reason: "key '\(constraint.name)': a field is missing", at: []))
                    continue
                }
                if tuple.contains(where: { $0 == nil }) { continue }
                if seen.contains(where: { $0 == tuple }) {
                    issues.append(.init(reason: "\(label(constraint)) '\(constraint.name)': duplicate value", at: []))
                } else {
                    seen.append(tuple)
                }
                tuples.append(tuple)
            }
            frame[constraint.name] = tuples
        }

        private func checkKeyref(
            _ constraint: IdentityConstraint,
            refer: String,
            at node: PureXML.Model.TreeNode,
            scopes: [[String: [[String?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            let keyTuples = scopes.reversed().compactMap { $0[refer] }.first ?? []
            for target in select(constraint.selector, at: node) {
                let tuple = fieldTuple(constraint.fields, at: target)
                if tuple.contains(where: { $0 == nil }) { continue }
                if !keyTuples.contains(where: { $0 == tuple }) {
                    issues.append(.init(reason: "keyref '\(constraint.name)': no matching key '\(refer)'", at: []))
                }
            }
        }

        // MARK: XPath helpers

        private func select(_ xpath: String, at node: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
            guard let query = try? PureXML.XPath.Query(xpath) else { return [] }
            return query.nodes(over: node)
        }

        private func fieldTuple(_ fields: [String], at node: PureXML.Model.TreeNode) -> [String?] {
            fields.map { field in
                guard let query = try? PureXML.XPath.Query(field), let value = try? query.value(at: node) else {
                    return nil
                }
                if let nodes = value.nodes, nodes.isEmpty { return nil }
                return value.string
            }
        }

        private func label(_ constraint: IdentityConstraint) -> String {
            constraint.kind == .key ? "key" : "unique"
        }
    }
}
