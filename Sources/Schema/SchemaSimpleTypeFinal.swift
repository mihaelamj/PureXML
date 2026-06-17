private typealias FinalNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 simple-type `final` enforcement for the list and union derivation
    /// directions (`st-props-correct` / Derivation Valid): a simple type whose
    /// `final` contains `list` may not be the `itemType` of a list, and one whose
    /// `final` contains `union` may not be a `memberType` of a union (`#all` forbids
    /// both, along with `restriction`). The restriction and extension directions are
    /// already enforced by `finalRespected`; the list and union directions were
    /// unchecked because `final="list"`/`"union"` is not modelled by
    /// `DerivationMethod`, so the `final` attribute is read directly here.
    ///
    /// Checked only for a self-contained schema (no `import`/`include`/`redefine`),
    /// where the single target namespace makes the names resolved by local name
    /// unambiguous; with external definitions the check stands down (a disclosed
    /// under-rejection).
    static func simpleTypeFinalErrors(_ schema: XSDTree, compositionLoaded: Bool, containers: [XSDTree]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: compositionLoaded) else { return [] }
        let finalOf = compositionLoaded ? mergedSimpleTypeFinalMap(containers) : simpleTypeFinalMap(schema)
        guard finalOf.values.contains(where: { !$0.isEmpty }) else { return [] }
        // The `final` map is keyed by local name; an `itemType`/`memberTypes`
        // reference must resolve to this schema's own target namespace before it is
        // matched, so a reference to a built-in (for example `xs:string`) is never
        // confused with a user type of the same local name.
        let bindings = FinalNode.namespaceBindings(of: schema)
        let target = FinalNode.attribute(schema, "targetNamespace")
        return listItemFinalErrors(schema, finalOf, bindings, target)
            + unionMemberFinalErrors(schema, finalOf, bindings, target)
    }

    private static func mergedSimpleTypeFinalMap(_ containers: [XSDTree]) -> [String: Set<String>] {
        var finalOf: [String: Set<String>] = [:]
        for container in containers where FinalNode.localName(container) != "redefine" {
            for (name, tokens) in simpleTypeFinalMap(container) {
                finalOf[name] = tokens
            }
        }
        return finalOf
    }

    /// Each named simple type mapped to the derivation tokens its `final` forbids.
    /// A type without its own `final` inherits the schema's `finalDefault` (its
    /// `{final}` property; XSD 1.0 Schemas §3.14.2), so `finalDefault="list"`
    /// makes every such type final for list derivation. An explicit `final=""`
    /// still overrides the default back to no restriction.
    private static func simpleTypeFinalMap(_ schema: XSDTree) -> [String: Set<String>] {
        let fallback = finalTokens(FinalNode.attribute(schema, "finalDefault"))
        var finalOf: [String: Set<String>] = [:]
        for simpleType in descendants(schema, named: "simpleType") {
            guard let name = FinalNode.attribute(simpleType, "name") else { continue }
            if let own = FinalNode.attribute(simpleType, "final") {
                finalOf[name] = finalTokens(own)
            } else {
                finalOf[name] = fallback
            }
        }
        return finalOf
    }

    private static func listItemFinalErrors(_ schema: XSDTree, _ finalOf: [String: Set<String>], _ bindings: [String: String], _ target: String?) -> [String] {
        var errors: [String] = []
        for list in descendants(schema, named: "list") {
            guard let item = FinalNode.attribute(list, "itemType"),
                  FinalNode.referenceNamespace(item, bindings) == target
            else { continue }
            let name = FinalNode.stripPrefix(item)
            if finalOf[name]?.contains("list") == true {
                errors.append("simple type '\(name)' is final for 'list' and may not be a list item type")
            }
        }
        return errors
    }

    private static func unionMemberFinalErrors(_ schema: XSDTree, _ finalOf: [String: Set<String>], _ bindings: [String: String], _ target: String?) -> [String] {
        var errors: [String] = []
        for union in descendants(schema, named: "union") {
            guard let members = FinalNode.attribute(union, "memberTypes") else { continue }
            for token in members.split(whereSeparator: \.isWhitespace) {
                guard FinalNode.referenceNamespace(String(token), bindings) == target else { continue }
                let name = FinalNode.stripPrefix(String(token))
                if finalOf[name]?.contains("union") == true {
                    errors.append("simple type '\(name)' is final for 'union' and may not be a union member type")
                }
            }
        }
        return errors
    }

    /// The derivation tokens a `final` value forbids; `#all` forbids every simple-type
    /// derivation (`restriction`, `list`, `union`).
    private static func finalTokens(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty else { return [] }
        var tokens: Set<String> = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            if token == "#all" { return ["restriction", "list", "union"] }
            tokens.insert(String(token))
        }
        return tokens
    }
}
