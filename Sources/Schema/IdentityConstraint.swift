public extension PureXML.Schema {
    /// The kind of an ``IdentityConstraint``, and for a keyref the name of the
    /// key it refers to.
    enum IdentityConstraintKind: Sendable, Equatable {
        /// Tuples must be distinct where present; a node missing a field is
        /// excluded rather than rejected.
        case unique
        /// Tuples must be distinct and every field must be present.
        case key
        /// Every tuple must equal a tuple of the named key or unique in scope.
        case keyref(refer: String)
    }

    /// An XSD identity constraint declared on an element: `xs:unique`, `xs:key`,
    /// or `xs:keyref`. The `selector` XPath chooses the nodes the constraint
    /// ranges over (relative to the declaring element), and each `field` XPath
    /// extracts one component of the value tuple from a selected node.
    struct IdentityConstraint: Sendable {
        public var name: String
        public var kind: IdentityConstraintKind
        public var selector: String
        public var fields: [String]
        /// Prefix-to-namespace bindings in scope where the constraint is declared
        /// in the schema. Selector and field XPath prefixes resolve against these
        /// (XSD Part 1, Identity-constraint Definition), not against the instance
        /// document, so `.//v:vehicle` works whatever prefix the instance uses.
        public var namespaceBindings: [String: String]

        public init(
            name: String,
            kind: IdentityConstraintKind,
            selector: String,
            fields: [String],
            namespaceBindings: [String: String] = [:],
        ) {
            self.name = name
            self.kind = kind
            self.selector = selector
            self.fields = fields
            self.namespaceBindings = namespaceBindings
        }
    }
}
