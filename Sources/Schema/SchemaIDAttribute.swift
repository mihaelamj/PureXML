extension PureXML.Schema.XSDParser {
    /// Schema-validity findings for the `id` attributes in a schema document. The
    /// `id` attribute on any XSD component is of type `xs:ID`, so each value must
    /// be a valid NCName and all values must be unique within the document
    /// (XSD Structures: `xs:ID` and the ID/IDREF constraints). The values were
    /// never checked, so a malformed (`id=""`, `id="123"`) or duplicated `id` left
    /// the schema wrongly accepted.
    ///
    /// Walks the one document rooted at `schema`; an included or imported document
    /// keeps its own `id` scope, so cross-document collisions are not flagged here.
    static func idAttributeErrors(_ schema: XSDTree) -> [String] {
        var errors: [String] = []
        var seen: Set<String> = []
        collectIDErrors(schema, into: &errors, seen: &seen)
        return errors
    }

    private static func collectIDErrors(_ node: XSDTree, into errors: inout [String], seen: inout Set<String>) {
        // `appinfo` and `documentation` hold arbitrary foreign content whose own
        // `id` attributes are not xs:ID; do not descend into them.
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if let id = unprefixedID(node) {
            if !PureXML.Schema.Lexical.isNCName(id) {
                errors.append("id attribute value '\(id)' is not a valid NCName")
            } else if !seen.insert(id).inserted {
                errors.append("duplicate id attribute value '\(id)' in the schema document")
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectIDErrors(child, into: &errors, seen: &seen)
        }
    }

    /// The value of the unprefixed, no-namespace `id` attribute (the xs:ID one),
    /// or nil. A prefixed attribute such as `xml:id` or a foreign `pre:id` is a
    /// different attribute and is not the schema-component identifier.
    private static func unprefixedID(_ node: XSDTree) -> String? {
        node.attributes.first { $0.name.prefix == nil && $0.name.localName == "id" }?.value
    }

    /// All compile-time schema-consistency findings, collected together so they are
    /// reported in one pass: `id` validity, schema-for-schemas structure, global
    /// component-name uniqueness, content-model determinism (UPA), and circular
    /// type derivation. The explicit return type keeps the type-checker from
    /// inferring a long concatenation.
    static func consistencyErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ containers: [XSDTree]) -> [String] {
        let structural = idAttributeErrors(schema) + structureErrors(schema) + componentNameErrors(schema)
        let determinism = PureXML.Schema.ContentModelDeterminism.violations(in: schema, context: context)
        let cycles = derivationCycleErrors(containers, context.namespaceBindings, context.targetNamespace)
            + circularReferenceErrors(containers, context.namespaceBindings, context.targetNamespace)
        let placement = allGroupReferencePlacementErrors(containers, context.namespaceBindings, context.targetNamespace)
        return structural + determinism + cycles + placement
    }

    /// Consistency findings that depend on the resolved named types, collected after
    /// `namedTypes` has populated them: unresolved references, attribute-use
    /// uniqueness and single-ID, ID-typed value constraints, and substitution-group
    /// member type derivation (`e-props-correct.4`).
    static func postNamedTypeErrors(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ containers: [XSDTree],
        _ derivation: DerivationTables,
        typeMaps: (global: [String: PureXML.Schema.ElementType], named: [String: PureXML.Schema.ElementType]),
    ) -> [String] {
        referenceErrors(schema, in: context, elements: typeMaps.global)
            + attributeUseErrors(containers, context)
            + idValueConstraintErrors(schema, context)
            + substitutionTypeErrors(schema, derivation, typeMaps.named)
    }
}
