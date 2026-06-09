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

        func validate(
            _ root: PureXML.Model.TreeNode,
            at path: [PureXML.Validation.PathKey] = [],
        ) -> [PureXML.Validation.ValidationError] {
            guard !constraints.isEmpty else { return [] }
            var issues: [PureXML.Validation.ValidationError] = []
            walk(root, at: path, scopes: [], into: &issues)
            return issues
        }

        private func walk(
            _ node: PureXML.Model.TreeNode,
            at path: [PureXML.Validation.PathKey],
            scopes: [[String: [[String?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            var frame: [String: [[String?]]] = [:]
            let declared = node.name.flatMap { constraints[$0.localName] } ?? []
            // Collect key and unique tuples first so a keyref on the same element
            // can resolve against them.
            for constraint in declared {
                collect(constraint, at: node, path: path, frame: &frame, into: &issues)
            }
            let visible = scopes + [frame]
            for constraint in declared {
                if case .keyref = constraint.kind {
                    checkKeyref(constraint, at: node, path: path, scopes: visible, into: &issues)
                }
            }
            let elementChildren = node.children.filter { $0.kind == .element }
            for (child, step) in zip(elementChildren, childSteps(elementChildren)) {
                walk(child, at: path + [step], scopes: visible, into: &issues)
            }
        }

        /// The coding-path step for each element child: its name, with a sibling
        /// index only when more than one child shares that name. Mirrors the
        /// complex-type validator's path construction so identity-constraint
        /// errors and content errors locate consistently.
        private func childSteps(_ children: [PureXML.Model.TreeNode]) -> [PureXML.Validation.PathKey] {
            var totals: [String: Int] = [:]
            for child in children {
                totals[child.name?.description ?? "", default: 0] += 1
            }
            var seen: [String: Int] = [:]
            return children.map { child in
                let name = child.name?.description ?? ""
                let index = (seen[name] ?? 0) + 1
                seen[name] = index
                return (totals[name] ?? 0) > 1 ? .element(name, index: index) : .element(name)
            }
        }

        private func isNonRef(_ constraint: IdentityConstraint) -> Bool {
            if case .keyref = constraint.kind { return false }
            return true
        }

        private func collect(
            _ constraint: IdentityConstraint,
            at node: PureXML.Model.TreeNode,
            path: [PureXML.Validation.PathKey],
            frame: inout [String: [[String?]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            guard isNonRef(constraint) else { return }
            var tuples: [[String?]] = []
            var seen: [[String?]] = []
            for target in select(constraint.selector, at: node) {
                let tuple = fieldTuple(constraint.fields, at: target)
                if constraint.kind == .key, tuple.contains(where: { $0 == nil }) {
                    issues.append(.init(reason: "key '\(constraint.name)': a field is missing", at: path))
                    continue
                }
                if tuple.contains(where: { $0 == nil }) { continue }
                if seen.contains(where: { $0 == tuple }) {
                    issues.append(.init(reason: "\(label(constraint)) '\(constraint.name)': duplicate value", at: path))
                } else {
                    seen.append(tuple)
                }
                tuples.append(tuple)
            }
            frame[constraint.name] = tuples
        }

        private func checkKeyref(
            _ constraint: IdentityConstraint,
            at node: PureXML.Model.TreeNode,
            path: [PureXML.Validation.PathKey],
            scopes: [[String: [[String?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            guard case let .keyref(refer) = constraint.kind else { return }
            let keyTuples = scopes.reversed().compactMap { $0[refer] }.first ?? []
            for target in select(constraint.selector, at: node) {
                let tuple = fieldTuple(constraint.fields, at: target)
                if tuple.contains(where: { $0 == nil }) { continue }
                if !keyTuples.contains(where: { $0 == tuple }) {
                    issues.append(.init(reason: "keyref '\(constraint.name)': no matching key '\(refer)'", at: path))
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
