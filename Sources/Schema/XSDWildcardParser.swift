extension PureXML.Schema.XSDParser {
    /// The effective `xs:anyAttribute` wildcard declared under `node`, including
    /// any `anyAttribute` on nested `attributeGroup` references.
    static func attributeWildcard(
        under node: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        visited: Set<String> = [],
    ) -> PureXML.Schema.Wildcard? {
        // A complex type's (or attribute group's) effective {attribute wildcard} is
        // the INTERSECTION of the wildcards it draws from its own `anyAttribute` and
        // from every referenced attribute group (XSD 1.0 `cos-aw-intersect`): an
        // attribute is admitted only if every source admits it. (An extension's
        // union with its base wildcard is handled separately, in XSDComplexContent.)
        var combined: PureXML.Schema.Wildcard?
        if let direct = PureXML.Schema.XSDNode.firstChild(node, named: "anyAttribute").map({ wildcard($0, context) }) {
            combined = PureXML.Schema.Wildcard.intersection(combined, direct)
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            guard PureXML.Schema.XSDNode.localName(child) == "attributeGroup",
                  let ref = PureXML.Schema.XSDNode.attribute(child, "ref")
            else { continue }
            let name = PureXML.Schema.XSDNode.stripPrefix(ref)
            if visited.contains(name) {
                guard context.redefinedAttributeGroups.contains(name),
                      let base = context.baseAttributeGroups[name],
                      let found = attributeWildcard(under: base, context, visited: visited)
                else { continue }
                combined = PureXML.Schema.Wildcard.intersection(combined, found)
                continue
            }
            guard let group = context.attributeGroups[name] else { continue }
            let scoped = context.scoped(for: PureXML.Schema.XSDNode.schemaOwner(group))
            if let found = attributeWildcard(under: group, scoped, visited: visited.union([name])) {
                combined = PureXML.Schema.Wildcard.intersection(combined, found)
            }
        }
        return combined
    }

    /// Parses a wildcard's `namespace` and `processContents` constraints.
    static func wildcard(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.Wildcard {
        let processContents: PureXML.Schema.ProcessContents = switch PureXML.Schema.XSDNode.attribute(node, "processContents") {
        case "skip": .skip
        case "lax": .lax
        default: .strict
        }
        let namespace = wildcardNamespace(PureXML.Schema.XSDNode.attribute(node, "namespace"), context)
        return PureXML.Schema.Wildcard(namespace: namespace, processContents: processContents, targetNamespace: context.targetNamespace)
    }

    private static func wildcardNamespace(_ value: String?, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.WildcardNamespace {
        switch value {
        case nil, "##any": return .any
        case "##other": return .other
        default:
            let uris = (value ?? "").split(whereSeparator: \.isWhitespace).map { token -> String in
                switch token {
                case "##targetNamespace": context.targetNamespace ?? ""
                case "##local": ""
                default: String(token)
                }
            }
            return .enumerated(Set(uris))
        }
    }
}
