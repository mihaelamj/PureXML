extension PureXML.Schema.IdentityValidator {
    /// The identity value a field takes from a declared `default`/`fixed` when the
    /// instance supplies none, or nil when the instance supplies a value (the
    /// caller then uses it). The substituted value carries the field's resolved
    /// type so it compares in the same value space as an explicit one.
    func defaultedValue(
        _ field: String,
        value: PureXML.XPath.Value,
        type: PureXML.Schema.SimpleType?,
        constraint: PureXML.Schema.IdentityConstraint,
        at node: PureXML.Model.TreeNode,
    ) -> FieldValue? {
        guard isFieldEmpty(field, value: value),
              let constrained = resolveFieldConstraint(field, constraint: constraint, at: node)
        else { return nil }
        return FieldValue(string: constrained.value, type: type, namespaceBindings: namespaceBindings(at: node))
    }

    /// Whether a field has no instance-supplied value, so a declared
    /// `default`/`fixed` may stand in. An `@attr` field is empty only when the
    /// attribute is ABSENT (empty node-set); a present attribute, even value "",
    /// is its own value. A `.` field is empty when the selected element has no
    /// character content; any other field is empty only on an empty node-set.
    func isFieldEmpty(_ field: String, value: PureXML.XPath.Value) -> Bool {
        guard let nodes = value.nodes else { return false }
        if field.hasPrefix("@") { return nodes.isEmpty }
        if field == "." {
            guard case let .tree(element)? = nodes.first, element.kind == .element else { return nodes.isEmpty }
            return !element.children.contains { $0.kind == .text || $0.kind == .cdata }
        }
        return nodes.isEmpty
    }

    /// The `default`/`fixed` declared on a field's target, keyed the same way as
    /// ``resolveFieldType(_:constraint:at:)`` so a multi-branch `.` selector
    /// resolves to its branch's element.
    func resolveFieldConstraint(
        _ field: String,
        constraint: PureXML.Schema.IdentityConstraint,
        at target: PureXML.Model.TreeNode,
    ) -> PureXML.Schema.ValueConstraint? {
        if field == ".", let local = target.name?.localName {
            let key = PureXML.Schema.XSDParser.identityFieldKey(constraint: constraint, field: field, targetLocal: local)
            if let value = fieldConstraints[key] { return value }
        }
        return fieldConstraints[PureXML.Schema.XSDParser.identityFieldKey(constraint: constraint, field: field)]
    }
}
