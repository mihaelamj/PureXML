private typealias XSDNode = PureXML.Schema.XSDNode
private typealias XSDContext = PureXML.Schema.XSDContext
private typealias Particle = PureXML.Schema.Particle
private typealias ComplexType = PureXML.Schema.ComplexType
private typealias ElementType = PureXML.Schema.ElementType
private typealias XSDSimpleParser = PureXML.Schema.XSDSimpleParser
private typealias BuiltinType = PureXML.Schema.BuiltinType
private typealias Wildcard = PureXML.Schema.Wildcard
private typealias SimpleType = PureXML.Schema.SimpleType

extension PureXML.Schema.XSDParser {
    // MARK: Element and type references

    static func elementType(_ node: PureXML.Model.TreeNode, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.ElementType {
        if let typeName = XSDNode.attribute(node, "type") {
            return typeReference(typeName, context, at: node)
        }
        if let inline = XSDNode.firstChild(node, named: "simpleType") {
            return .simple(XSDSimpleParser.simpleType(inline, context))
        }
        if let inline = XSDNode.firstChild(node, named: "complexType") {
            return .complex(complexType(inline, context))
        }
        return .complex(anyType)
    }

    private static func typeReference(_ typeName: String, _ context: XSDContext, at node: XSDTree? = nil) -> ElementType {
        let bindings = node.map {
            PureXML.Schema.XSDParser.namespaceBindingsInScope(of: $0, defaultBindings: context.namespaceBindings)
        } ?? context.namespaceBindings
        let local = XSDNode.stripPrefix(typeName)
        let uri = XSDNode.schemaComponentNamespace(typeName, bindings, targetNamespace: context.targetNamespace)
        if uri == PureXML.Schema.XSDParser.xsdNamespace {
            if let builtin = BuiltinType(rawValue: local) {
                return .simple(SimpleType(base: builtin))
            }
            if local == "anySimpleType" {
                return .simple(SimpleType(base: .string, isAnySimpleType: true))
            }
            if local == "anyType" {
                return .complex(anyType)
            }
            if let item = XSDSimpleParser.listBuiltinItem(local) {
                return .simple(.list(item: SimpleType(base: item), isBuiltinList: true))
            }
        }
        return .typeReference(typeDeclarationKey(local, namespaceURI: uri))
    }

    /// The ur-type `xsd:anyType`. Per XSD 1.0 §3.4.7 its element and attribute
    /// wildcards are `lax`, not skip: a child or attribute that has a global
    /// declaration is validated against it, while undeclared content is admitted.
    private static var anyType: ComplexType {
        ComplexType(
            attributeWildcard: Wildcard(processContents: .lax),
            content: .mixed(Particle(minOccurs: 0, maxOccurs: nil, term: .wildcard(Wildcard(processContents: .lax)))),
        )
    }
}
