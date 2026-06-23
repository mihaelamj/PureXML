extension PureXML.Schema.XSDParser {
    /// The effective `xs:anyAttribute` wildcard declared under `node`, including
    /// any `anyAttribute` on nested `attributeGroup` references.
    static func attributeWildcard(
        under node: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        visited: Set<String> = [],
    ) -> PureXML.Schema.Wildcard? {
        // Best-effort view for type building: a not-expressible intersection makes
        // the schema invalid (flagged by SchemaWildcardExpressibility), so the type
        // it would have carried is never used to validate a valid instance.
        switch attributeWildcardCombination(under: node, context, visited: visited) {
        case let .constraint(wildcard): wildcard
        case .notExpressible: nil
        }
    }

    /// The effective `xs:anyAttribute` wildcard under `node`, or `notExpressible`
    /// when intersecting the sources yields no expressible {namespace constraint}.
    static func attributeWildcardCombination(
        under node: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        visited: Set<String> = [],
    ) -> PureXML.Schema.WildcardCombination {
        // A complex type's (or attribute group's) effective {attribute wildcard} is
        // the INTERSECTION of the wildcards it draws from its own `anyAttribute` and
        // from every referenced attribute group (XSD 1.0 `cos-aw-intersect`): an
        // attribute is admitted only if every source admits it. (An extension's
        // union with its base wildcard is handled separately, in XSDComplexContent.)
        var combined: PureXML.Schema.WildcardCombination = .constraint(nil)
        func merge(_ next: PureXML.Schema.Wildcard?) {
            guard case let .constraint(current) = combined else { return }
            combined = PureXML.Schema.Wildcard.intersection(current, next)
        }
        if let direct = PureXML.Schema.XSDNode.firstChild(node, named: "anyAttribute").map({ wildcard($0, context) }) {
            merge(direct)
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            guard case .constraint = combined else { break }
            guard PureXML.Schema.XSDNode.localName(child) == "attributeGroup",
                  let ref = PureXML.Schema.XSDNode.attribute(child, "ref")
            else { continue }
            switch referencedGroupWildcard(PureXML.Schema.XSDNode.stripPrefix(ref), context, visited: visited) {
            case let .constraint(found): merge(found)
            case .notExpressible: combined = .notExpressible
            }
        }
        return combined
    }

    /// The effective wildcard combination of the attribute group referenced by
    /// `name`, resolving a redefine self-reference against the group's base.
    private static func referencedGroupWildcard(
        _ name: String,
        _ context: PureXML.Schema.XSDContext,
        visited: Set<String>,
    ) -> PureXML.Schema.WildcardCombination {
        if visited.contains(name) {
            guard context.redefinedAttributeGroups.contains(name),
                  let base = context.baseAttributeGroups[name]
            else { return .constraint(nil) }
            return attributeWildcardCombination(under: base, context, visited: visited)
        }
        guard let group = context.attributeGroups[name] else { return .constraint(nil) }
        let scoped = context.scoped(for: PureXML.Schema.XSDNode.schemaOwner(group))
        return attributeWildcardCombination(under: group, scoped, visited: visited.union([name]))
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
        case "##other":
            // `##other` = any namespace name other than the target, never absent.
            // With no target namespace it is simply "any non-absent namespace".
            if let target = context.targetNamespace, !target.isEmpty { return .notNamespace(target) }
            return .notAbsent
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
