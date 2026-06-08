extension PureXML.Schema.XSDParser {
    /// The `xs:anyAttribute` wildcard declared directly under `node`, if any.
    static func attributeWildcard(under node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.Wildcard? {
        PureXML.Schema.XSDNode.firstChild(node, named: "anyAttribute").map { wildcard($0, context) }
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
