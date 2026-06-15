private typealias SubTypeNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `e-props-correct.4`: the {type definition} of an element declaration
    /// must be validly derived from the {type definition} of the head of every
    /// substitution group it affiliates to (any type derives from the head's
    /// ur-type, so an untyped head admits any member). A member whose type is
    /// unrelated to the head's, for instance an element of type `xs:int` declaring
    /// `substitutionGroup` of a head typed `xs:string`, leaves the schema wrongly
    /// accepted.
    ///
    /// Scope and conservatism:
    /// - Checked only for a self-contained schema (no `import`/`include`/`redefine`),
    ///   where the derivation table is complete and, with one target namespace, the
    ///   names resolved by local name are unambiguous.
    /// - The member's type is read from its own `type` attribute and the head's from
    ///   a map of the top-level (global) element declarations only, so a local
    ///   element sharing a name does not supply either type.
    /// - `typeDerivesOrEqual` models the restriction/extension chain and the built-in
    ///   lattice but not the list/union variety rules (`cos-st-derived-ok` clauses
    ///   2.3 and 2.4: a type derives from a union if it derives from one of the
    ///   union's member types). When either type is a list or union the check stands
    ///   down rather than reject a valid member, a disclosed under-rejection.
    static func substitutionTypeErrors(_ schema: XSDTree, _ tables: DerivationTables, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !hasExternalDocuments(schema) else { return [] }
        let globals = SubTypeNode.elementChildren(schema).filter {
            SubTypeNode.localName($0) == "element" && $0.name?.namespaceURI == xsdNamespace
        }
        var globalElementType: [String: String] = [:]
        for global in globals {
            if let name = SubTypeNode.attribute(global, "name"), let type = SubTypeNode.attribute(global, "type") {
                globalElementType[name] = SubTypeNode.stripPrefix(type)
            }
        }
        var errors: [String] = []
        for element in globals {
            guard let member = SubTypeNode.attribute(element, "name"),
                  let headReference = SubTypeNode.attribute(element, "substitutionGroup"),
                  // An element with no `type` attribute has an inline or absent type:
                  // an untyped member inherits the head's type and derives trivially,
                  // so it is correctly skipped.
                  let memberType = SubTypeNode.attribute(element, "type").map(SubTypeNode.stripPrefix)
            else { continue }
            let head = SubTypeNode.stripPrefix(headReference)
            // No entry means an untyped head (the ur-type, which admits any member) or
            // an unresolved head; either way there is nothing to reject here.
            guard let headType = globalElementType[head] else { continue }
            // List/union derivation is not modelled; stand down to avoid rejecting a
            // valid member (e.g. an integer member of a union-typed head).
            guard !isListOrUnion(memberType, types), !isListOrUnion(headType, types) else { continue }
            if !PureXML.Schema.ParticleRestriction.typeDerivesOrEqual(memberType, headType, tables.typeDerivation, types) {
                errors.append("element '\(member)' may not be in the substitution group of '\(head)': its type '\(memberType)' is not derived from '\(headType)'")
            }
        }
        return errors
    }

    /// Whether the named type is a list- or union-variety simple type, whose
    /// derivation rules `typeDerivesOrEqual` does not model. A built-in or unknown
    /// name is treated as atomic.
    private static func isListOrUnion(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool {
        guard case let .simple(simple)? = types[name] else { return false }
        switch simple.variety {
        case .atomic: return false
        case .list, .union: return true
        }
    }

    /// Whether the schema document composes other documents, so a referenced
    /// definition may live outside the loaded derivation table.
    private static func hasExternalDocuments(_ schema: XSDTree) -> Bool {
        SubTypeNode.elementChildren(schema).contains { child in
            let kind = SubTypeNode.localName(child)
            return kind == "import" || kind == "include" || kind == "redefine"
        }
    }
}
