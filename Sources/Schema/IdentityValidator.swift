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

/// One field of an identity tuple: its lexical value and the simple type it
/// compares in (from the node's `xsi:type`, if any). Two field values are equal
/// when they denote the same value: in the value space of their type when both
/// share a built-in base (so `3.0` equals `3` for `xsd:decimal`), otherwise by
/// lexical form.
private struct FieldValue: Equatable {
    let string: String
    let type: PureXML.Schema.SimpleType?
    let namespaceBindings: [String: String]

    init(string: String, type: PureXML.Schema.SimpleType?, namespaceBindings: [String: String] = [:]) {
        self.string = string
        self.type = type
        self.namespaceBindings = namespaceBindings
    }

    static func == (lhs: FieldValue, rhs: FieldValue) -> Bool {
        if let left = lhs.qnameValue, let right = rhs.qnameValue, left.uri == right.uri, left.local == right.local {
            return true
        }
        if let lhsType = lhs.type, let rhsType = rhs.type {
            if lhsType.base == rhsType.base {
                return lhsType.valueMatches(lhs.string, literal: rhs.string)
            }
            return false
        }
        return lhs.string == rhs.string
    }

    private var qnameValue: (uri: String?, local: String)? {
        let trimmed = string.trimmingXMLWhitespace()
        guard trimmed.contains(":") else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let uri = namespaceBindings[parts[0]] ?? (parts[0].isEmpty ? namespaceBindings[""] : nil)
        return (uri, parts[1])
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
        /// Simple types for identity-constraint fields keyed by
        /// ``XSDParser/identityFieldKey(selector:field:)``.
        let fieldTypes: [String: SimpleType]
        /// Global element and type declarations for runtime field typing.
        let types: [String: ElementType]
        /// Selector and field XPaths compiled once per run, not per element.
        private let cache = XPathQueryCache()

        init(
            constraints: [String: [IdentityConstraint]],
            fieldTypes: [String: SimpleType] = [:],
            types: [String: ElementType] = [:],
        ) {
            self.constraints = constraints
            self.fieldTypes = fieldTypes
            self.types = types
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
            scopes: [[String: [[FieldValue?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            var frame: [String: [[FieldValue?]]] = [:]
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
            PureXML.Validation.PathKey.steps(forChildNames: children.map { $0.name?.description ?? "" })
        }

        /// The coding-path step from a `target` down to the single field a
        /// constraint names, so an error locates the offending value (`@id`, a
        /// child element) rather than just the target. Empty for a multi-field
        /// constraint or a complex field path, in which case the error stays on the
        /// target.
        private func fieldStep(_ fields: [String], at target: PureXML.Model.TreeNode, namespaces: [String: String]) -> [PureXML.Validation.PathKey] {
            guard fields.count == 1 else { return [] }
            let field = fields[0]
            if field.hasPrefix("@"), !field.dropFirst().contains(where: { $0 == "/" || $0 == "[" }) {
                return [.attribute(String(field.dropFirst()))]
            }
            let isSimpleName = !field.contains(where: { "/@[(".contains($0) })
            if isSimpleName, let child = select(field, at: target, namespaces: namespaces).first, child.kind == .element {
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
            frame: inout [String: [[FieldValue?]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            guard isNonRef(constraint) else { return }
            var tuples: [[FieldValue?]] = []
            var seen: [[FieldValue?]] = []
            for target in select(constraint.selector, at: node, namespaces: constraint.namespaceBindings) {
                let targetPath = path + steps(from: node, to: target)
                if let error = fieldCardinalityError(constraint, at: target, path: targetPath) {
                    issues.append(error)
                    continue
                }
                let tuple = fieldTuple(constraint.fields, at: target, constraint: constraint)
                if constraint.kind == .key, tuple.contains(where: { $0 == nil }) {
                    issues.append(.init(
                        reason: "key '\(constraint.name)': a field is missing",
                        at: targetPath + fieldStep(constraint.fields, at: target, namespaces: constraint.namespaceBindings),
                    ))
                    continue
                }
                if tuple.contains(where: { $0 == nil }) { continue }
                if seen.contains(where: { $0 == tuple }) {
                    issues.append(.init(
                        reason: "\(label(constraint)) '\(constraint.name)': duplicate value",
                        at: targetPath + fieldStep(constraint.fields, at: target, namespaces: constraint.namespaceBindings),
                    ))
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
            scopes: [[String: [[FieldValue?]]]],
            into issues: inout [PureXML.Validation.ValidationError],
        ) {
            guard case let .keyref(refer) = constraint.kind else { return }
            let keyTuples = scopes.reversed().compactMap { $0[refer] }.first ?? []
            for target in select(constraint.selector, at: node, namespaces: constraint.namespaceBindings) {
                let targetPath = path + steps(from: node, to: target)
                if let error = fieldCardinalityError(constraint, at: target, path: targetPath) {
                    issues.append(error)
                    continue
                }
                let tuple = fieldTuple(constraint.fields, at: target, constraint: constraint)
                if tuple.contains(where: { $0 == nil }) { continue }
                if !keyTuples.contains(where: { $0 == tuple }) {
                    issues.append(.init(
                        reason: "keyref '\(constraint.name)': no matching key '\(refer)'",
                        at: targetPath + fieldStep(constraint.fields, at: target, namespaces: constraint.namespaceBindings),
                    ))
                }
            }
        }

        /// The error when a field of `constraint` selects more than one node at
        /// `target`. A field must evaluate to a node-set with at most one member
        /// (Identity-constraint Definition; cvc-identity-constraint.3); selecting
        /// several is a violation, not a multi-valued key.
        private func fieldCardinalityError(
            _ constraint: IdentityConstraint,
            at target: PureXML.Model.TreeNode,
            path targetPath: [PureXML.Validation.PathKey],
        ) -> PureXML.Validation.ValidationError? {
            for field in constraint.fields where select(field, at: target, namespaces: constraint.namespaceBindings).count > 1 {
                return .init(
                    reason: "\(label(constraint)) '\(constraint.name)': field '\(field)' must select at most one node",
                    at: targetPath + fieldStep(constraint.fields, at: target, namespaces: constraint.namespaceBindings),
                )
            }
            return nil
        }

        // MARK: XPath helpers

        private func select(_ xpath: String, at node: PureXML.Model.TreeNode, namespaces: [String: String]) -> [PureXML.Model.TreeNode] {
            guard let query = cache.query(xpath) else { return [] }
            return query.nodes(over: node, namespaces: namespaces)
        }

        private func fieldTuple(_ fields: [String], at node: PureXML.Model.TreeNode, constraint: IdentityConstraint) -> [FieldValue?] {
            // The field XPath's prefixes resolve against the schema (where the
            // constraint is declared); a QName field VALUE resolves against the
            // instance, so the FieldValue keeps the instance bindings.
            let instanceNamespaces = namespaceBindings(at: node)
            return fields.map { field in
                guard let query = cache.query(field),
                      let value = try? query.value(at: node, namespaces: constraint.namespaceBindings)
                else {
                    return nil
                }
                if let nodes = value.nodes, nodes.isEmpty { return nil }
                let type = resolveFieldType(field, constraint: constraint, at: node)
                    ?? Self.effectiveType(of: value)
                return FieldValue(string: value.string, type: type, namespaceBindings: instanceNamespaces)
            }
        }

        /// Prefix bindings in scope at `node`, gathered from ancestor elements.
        private func namespaceBindings(at node: PureXML.Model.TreeNode) -> [String: String] {
            var chain: [PureXML.Model.TreeNode] = []
            var current: PureXML.Model.TreeNode? = node
            while let element = current, element.kind == .element {
                chain.append(element)
                current = element.parent
            }
            var bindings: [String: String] = [:]
            for element in chain.reversed() {
                for attribute in element.attributes {
                    if attribute.name.prefix == "xmlns" {
                        bindings[attribute.name.localName] = attribute.value
                    } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                        bindings[""] = attribute.value
                    }
                }
            }
            return bindings
        }

        /// The simple type a field value compares in: the built-in named by the
        /// selected node's `xsi:type`, when present. Identity-constraint values
        /// compare in their value space, so two `xsi:type="xsd:decimal"` fields
        /// `3.0` and `3` are the same value and violate a `unique`/`key`. With no
        /// `xsi:type` the comparison falls back to the lexical form (the type
        /// declared in the schema is not threaded into identity validation).
        private func resolveFieldType(_ field: String, constraint: IdentityConstraint, at target: PureXML.Model.TreeNode) -> SimpleType? {
            if field == ".", let local = target.name?.localName {
                if let type = fieldTypes[PureXML.Schema.XSDParser.identityFieldKey(constraint: constraint, field: field, targetLocal: local)] {
                    return type
                }
                guard let name = target.name else { return nil }
                if let declaration = types[PureXML.Schema.XSDParser.elementDeclarationKey(name)] {
                    return simpleType(of: declaration)
                }
                if let declaration = types[PureXML.Schema.XSDParser.elementKey(name.localName)] {
                    return simpleType(of: declaration)
                }
            }
            return fieldTypes[PureXML.Schema.XSDParser.identityFieldKey(constraint: constraint, field: field)]
        }

        private func simpleType(of declaration: ElementType) -> SimpleType? {
            switch declaration {
            case let .simple(simple): simple
            case let .complex(complex):
                if case let .simpleContent(simple) = complex.content { simple } else { nil }
            case .typeReference: nil
            }
        }

        private static func effectiveType(of value: PureXML.XPath.Value) -> SimpleType? {
            guard let nodes = value.nodes, case let .tree(treeNode)? = nodes.first,
                  treeNode.kind == .element, let local = xsiTypeLocalName(of: treeNode),
                  let builtin = BuiltinType(rawValue: local)
            else { return nil }
            return SimpleType(base: builtin)
        }

        /// The local name of a tree node's `xsi:type` attribute value, recognized by
        /// the schema-instance namespace or the conventional `xsi` prefix, or nil.
        private static func xsiTypeLocalName(of node: PureXML.Model.TreeNode) -> String? {
            let schemaInstance = "http://www.w3.org/2001/XMLSchema-instance"
            guard let attribute = node.attributes.first(where: {
                $0.name.localName == "type" && ($0.name.namespaceURI == schemaInstance || $0.name.prefix == "xsi")
            }) else { return nil }
            return attribute.value.split(separator: ":").last.map(String.init) ?? attribute.value
        }

        private func label(_ constraint: IdentityConstraint) -> String {
            constraint.kind == .key ? "key" : "unique"
        }
    }
}

extension PureXML.Schema.IdentityValidator {
    /// The coding-path steps from the constraint-bearing `container` down to a
    /// selected `target`, so an identity error locates the actual offending
    /// element rather than the element that merely declares the constraint.
    /// Returns an empty path if `target` is not a descendant of `container`.
    func steps(from container: PureXML.Model.TreeNode, to target: PureXML.Model.TreeNode) -> [PureXML.Validation.PathKey] {
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
}
