struct ReferenceCheckContext {
    let types: Set<String>
    let pools: [String: Set<String>]
    let bindings: [String: String]
    let targetNamespace: String?
    let foreignPools: [String?: [String: Set<String>]]
    /// A no-`targetNamespace` included schema whose globals adopt the includer's namespace.
    let chameleonNamespace: Bool
}

extension PureXML.Schema.XSDParser {
    /// The built-in type names a reference may name without a declaration: the
    /// XSD Part 2 datatypes, the built-in list types, and the ur-types.
    static let referenceBuiltins: Set<String> = {
        var names = Set(PureXML.Schema.BuiltinType.allCases.map(\.rawValue))
        names.formUnion(["anyType", "anySimpleType", "anyAtomicType", "NOTATION", "IDREFS", "ENTITIES", "NMTOKENS"])
        return names
    }()

    /// Namespaces commonly referenced without a loadable schema document (`xml:`,
    /// and similar). References into them stand down rather than being rejected.
    static let unloadedReferenceNamespaces: Set<String> = [
        "http://www.w3.org/XML/1998/namespace",
    ]

    static func referenceURI(for qname: String, bindings: [String: String]) -> String? {
        let prefix = PureXML.Schema.XSDNode.prefix(qname)
        var uri = prefix.flatMap { bindings[$0] } ?? bindings[""]
        if uri == nil, prefix == "xml" {
            uri = "http://www.w3.org/XML/1998/namespace"
        }
        return uri
    }

    static func isUndeclaredReferenceType(_ qname: String, in context: ReferenceCheckContext) -> Bool {
        let uri = referenceURI(for: qname, bindings: context.bindings)
        let localPart = referenceLocalName(qname)
        if uri == xsdNamespace {
            if context.targetNamespace == xsdNamespace {
                return !referenceBuiltins.contains(localPart) && !context.types.contains(localPart)
            } else {
                return !referenceBuiltins.contains(localPart)
            }
        }
        if let uri, unloadedReferenceNamespaces.contains(uri) {
            return false
        }
        let inTargetNamespace = uri == context.targetNamespace
            || ((uri == nil || uri == "") && (context.targetNamespace == nil || context.targetNamespace == ""))
        if inTargetNamespace {
            return !context.types.contains(localPart)
        }
        if let foreignTypes = context.foreignPools[uri]?["type"] {
            return !foreignTypes.contains(localPart)
        }
        if uri == nil || uri == "" {
            return !context.types.contains(localPart)
        }
        return false
    }

    static func isUndeclaredReferenceRef(_ qname: String, poolName: String, in context: ReferenceCheckContext) -> Bool {
        let uri = referenceURI(for: qname, bindings: context.bindings)
        let localPart = referenceLocalName(qname)
        let inTargetNamespace = uri == context.targetNamespace
            || ((uri == nil || uri == "") && (context.targetNamespace == nil || context.targetNamespace == ""))
        if inTargetNamespace {
            return context.pools[poolName]?.contains(localPart) != true
        }
        if let uri, unloadedReferenceNamespaces.contains(uri) {
            return false
        }
        if let foreign = context.foreignPools[uri]?[poolName] {
            return !foreign.contains(localPart)
        }
        if uri == xsdNamespace {
            // The XSD namespace declares no referenceable user component (element,
            // group, attribute, attribute group), so a reference resolving to it is
            // undeclared. This is reached when an unprefixed reference picks up a
            // default `xmlns` of the XSD namespace, so it is NOT in the target
            // namespace (XSTS xsd013/xsd014); the schema that itself targets the XSD
            // namespace is the `inTargetNamespace` case above, and a genuinely loaded
            // XSD-namespace document is the `foreignPools` case just before.
            return true
        }
        if uri == nil || uri == "" {
            if context.chameleonNamespace, context.pools[poolName]?.contains(localPart) == true { return false }
            if !(context.targetNamespace == nil || context.targetNamespace == "") { return true }
            return context.pools[poolName]?.contains(localPart) != true
        }
        return false
    }

    /// The local part of a QName reference, after the whitespace normalization a
    /// `whiteSpace="collapse"` QName attribute receives (a value may be written
    /// with surrounding or, harmlessly, interior whitespace).
    static func referenceLocalName(_ qname: String) -> String {
        PureXML.Schema.XSDNode.stripPrefix(qname.trimmingXMLWhitespace())
    }
}
