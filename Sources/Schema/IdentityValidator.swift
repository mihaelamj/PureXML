/// Compiles each distinct XPath string once per validation run, so a
/// constraint's selector and field queries are not re-parsed at every element
/// the walk visits. A string that fails to compile caches as nil (no match).
private final class XPathQueryCache {
    private var queries: [String: PureXML.XPath.Query?] = [:]

    func query(_ xpath: String) -> PureXML.XPath.Query? {
        if let cached = queries[xpath] { return cached }
        let compiled = try? PureXML.XPath.Query(xpath)
        queries[xpath] = compiled
        return compiled
    }
}

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
        /// Selector and field XPaths compiled once per run, not per element.
        private let cache = XPathQueryCache()

        init(constraints: [String: [IdentityConstraint]]) {
            self.constraints = constraints
        }

        func validate(
            _ root: PureXML.Model.TreeNode,
            at path: [PureXML.Validation.PathKey] = [],
        ) -> [PureXML.Validation.ValidationError] {
            guard !constraints.isEmpty else { return [] }
            // A selector or field XPath that does not compile is a schema-author
            // error, reported once up front rather than silently disabling the
            // constraint (the broken query still evaluates as no-match below).
            var issues: [PureXML.Validation.ValidationError] = compileErrors(at: path)
            walk(root, at: path, scopes: [], into: &issues)
            return issues
        }

        /// One located error per constraint XPath that fails to compile, in a
        /// deterministic order. The failed compilations are cached, so the walk
        /// afterwards treats those constraints as matching nothing.
        private func compileErrors(at path: [PureXML.Validation.PathKey]) -> [PureXML.Validation.ValidationError] {
            var errors: [PureXML.Validation.ValidationError] = []
            for key in constraints.keys.sorted() {
                for constraint in constraints[key] ?? [] {
                    if cache.query(constraint.selector) == nil {
                        errors.append(.init(reason: "identity constraint '\(constraint.name)': invalid selector XPath '\(constraint.selector)'", at: path))
                    }
                    for field in constraint.fields where cache.query(field) == nil {
                        errors.append(.init(reason: "identity constraint '\(constraint.name)': invalid field XPath '\(field)'", at: path))
                    }
                }
            }
            return errors
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

        /// The coding-path steps from the constraint-bearing `container` down to a
        /// selected `target`, so an identity error locates the actual offending
        /// element rather than the element that merely declares the constraint.
        /// Returns an empty path if `target` is not a descendant of `container`.
        private func steps(from container: PureXML.Model.TreeNode, to target: PureXML.Model.TreeNode) -> [PureXML.Validation.PathKey] {
            var chain: [PureXML.Model.TreeNode] = []
            var current = target
            while current !== container {
                guard let parent = current.parent else { return [] }
                chain.append(current)
                current = parent
            }
            var steps: [PureXML.Validation.PathKey] = []
            var parent = container
            for node in chain.reversed() {
                let name = node.name?.description ?? ""
                let siblings = parent.children.filter { $0.kind == .element && ($0.name?.description ?? "") == name }
                if siblings.count > 1, let index = siblings.firstIndex(where: { $0 === node }) {
                    steps.append(.element(name, index: index + 1))
                } else {
                    steps.append(.element(name))
                }
                parent = node
            }
            return steps
        }

        /// The coding-path step from a `target` down to the single field a
        /// constraint names, so an error locates the offending value (`@id`, a
        /// child element) rather than just the target. Empty for a multi-field
        /// constraint or a complex field path, in which case the error stays on the
        /// target.
        private func fieldStep(_ fields: [String], at target: PureXML.Model.TreeNode) -> [PureXML.Validation.PathKey] {
            guard fields.count == 1 else { return [] }
            let field = fields[0]
            if field.hasPrefix("@"), !field.dropFirst().contains(where: { $0 == "/" || $0 == "[" }) {
                return [.attribute(String(field.dropFirst()))]
            }
            let isSimpleName = !field.contains(where: { "/@[(".contains($0) })
            if isSimpleName, let child = select(field, at: target).first, child.kind == .element {
                return steps(from: target, to: child)
            }
            return []
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
                let targetPath = path + steps(from: node, to: target)
                if constraint.kind == .key, tuple.contains(where: { $0 == nil }) {
                    issues.append(.init(reason: "key '\(constraint.name)': a field is missing", at: targetPath + fieldStep(constraint.fields, at: target)))
                    continue
                }
                if tuple.contains(where: { $0 == nil }) { continue }
                if seen.contains(where: { $0 == tuple }) {
                    issues.append(.init(reason: "\(label(constraint)) '\(constraint.name)': duplicate value", at: targetPath + fieldStep(constraint.fields, at: target)))
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
                    let targetPath = path + steps(from: node, to: target)
                    issues.append(.init(reason: "keyref '\(constraint.name)': no matching key '\(refer)'", at: targetPath + fieldStep(constraint.fields, at: target)))
                }
            }
        }

        // MARK: XPath helpers

        private func select(_ xpath: String, at node: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
            guard let query = cache.query(xpath) else { return [] }
            return query.nodes(over: node)
        }

        private func fieldTuple(_ fields: [String], at node: PureXML.Model.TreeNode) -> [String?] {
            fields.map { field in
                guard let query = cache.query(field), let value = try? query.value(at: node) else {
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
