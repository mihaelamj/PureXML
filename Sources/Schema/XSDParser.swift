private typealias Tree = PureXML.Model.TreeNode

/// Tree-access helpers shared by the schema parser. File-scope and private.
private enum XSDNode {
    static func localName(_ node: Tree) -> String? {
        node.name?.localName
    }

    static func attribute(_ node: Tree, _ name: String) -> String? {
        node.attributes.first { $0.name.localName == name }?.value
    }

    static func elementChildren(_ node: Tree) -> [Tree] {
        node.children.filter { $0.kind == .element }
    }

    static func children(_ node: Tree, named name: String) -> [Tree] {
        elementChildren(node).filter { localName($0) == name }
    }

    static func firstChild(_ node: Tree, named name: String) -> Tree? {
        children(node, named: name).first
    }

    static func stripPrefix(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    static func occurrence(_ node: Tree) -> (min: Int, max: Int?) {
        let minimum = attribute(node, "minOccurs").flatMap(Int.init) ?? 1
        let maximumText = attribute(node, "maxOccurs")
        let maximum: Int? = maximumText == "unbounded" ? nil : (maximumText.flatMap(Int.init) ?? 1)
        return (minimum, maximum)
    }
}

extension PureXML.Schema {
    /// Parses an XSD schema document into its global element declarations and its
    /// named-type table. Matches the schema vocabulary by local name, so the XML
    /// Schema namespace prefix may be anything. Supports global and local element
    /// declarations, named and inline simple and complex types, `sequence`,
    /// `choice`, and `all` model groups with occurrence, attribute uses, simple
    /// content, and the full facet set.
    enum XSDParser {
        static func parse(
            _ xsd: String,
        ) throws -> (elements: [String: ElementType], types: [String: ElementType]) {
            let root = try PureXML.parseTree(xsd)
            guard let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" }) else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            var simpleTypes: [String: SimpleType] = [:]
            for node in XSDNode.children(schema, named: "simpleType") {
                if let name = XSDNode.attribute(node, "name") {
                    simpleTypes[name] = simpleType(node, simpleTypes)
                }
            }
            var types: [String: ElementType] = simpleTypes.mapValues(ElementType.simple)
            for node in XSDNode.children(schema, named: "complexType") {
                if let name = XSDNode.attribute(node, "name") {
                    types[name] = .complex(complexType(node, simpleTypes))
                }
            }
            var elements: [String: ElementType] = [:]
            for node in XSDNode.children(schema, named: "element") {
                if let name = XSDNode.attribute(node, "name") {
                    elements[name] = elementType(node, simpleTypes)
                }
            }
            return (elements, types)
        }

        // MARK: Element and type references

        private static func elementType(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> ElementType {
            if let typeName = XSDNode.attribute(node, "type") {
                return typeReference(typeName)
            }
            if let inline = XSDNode.firstChild(node, named: "simpleType") {
                return .simple(simpleType(inline, simpleTypes))
            }
            if let inline = XSDNode.firstChild(node, named: "complexType") {
                return .complex(complexType(inline, simpleTypes))
            }
            return .complex(anyType)
        }

        private static func typeReference(_ typeName: String) -> ElementType {
            let local = XSDNode.stripPrefix(typeName)
            if let builtin = BuiltinType(rawValue: local) {
                return .simple(SimpleType(base: builtin))
            }
            return .typeReference(local)
        }

        private static func simpleTypeReference(_ typeName: String, _ simpleTypes: [String: SimpleType]) -> SimpleType {
            let local = XSDNode.stripPrefix(typeName)
            if let builtin = BuiltinType(rawValue: local) { return SimpleType(base: builtin) }
            return simpleTypes[local] ?? SimpleType(base: .string)
        }

        private static var anyType: ComplexType {
            ComplexType(
                allowsOtherAttributes: true,
                content: .mixed(Particle(minOccurs: 0, maxOccurs: nil, term: .wildcard(Wildcard()))),
            )
        }

        // MARK: Simple types and facets

        private static func simpleType(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> SimpleType {
            guard let restriction = XSDNode.firstChild(node, named: "restriction") else {
                return SimpleType(base: .string)
            }
            let baseName = XSDNode.stripPrefix(XSDNode.attribute(restriction, "base") ?? "string")
            var base = BuiltinType.string
            var facets = Facets()
            if let builtin = BuiltinType(rawValue: baseName) {
                base = builtin
            } else if let parent = simpleTypes[baseName] {
                base = parent.base
                facets = parent.facets
            }
            applyFacets(restriction, into: &facets)
            return SimpleType(base: base, facets: facets)
        }

        private static func applyFacets(_ restriction: Tree, into facets: inout Facets) {
            for facet in XSDNode.elementChildren(restriction) {
                let value = XSDNode.attribute(facet, "value")
                applyStringFacet(XSDNode.localName(facet), value, into: &facets)
                applyNumericFacet(XSDNode.localName(facet), value, into: &facets)
            }
        }

        private static func applyStringFacet(_ name: String?, _ value: String?, into facets: inout Facets) {
            switch name {
            case "pattern": if let value { facets.patterns.append(value) }
            case "enumeration": if let value { facets.enumeration = (facets.enumeration ?? []) + [value] }
            case "minInclusive": facets.minInclusive = value
            case "maxInclusive": facets.maxInclusive = value
            case "minExclusive": facets.minExclusive = value
            case "maxExclusive": facets.maxExclusive = value
            case "whiteSpace": facets.whiteSpace = whiteSpace(value)
            default: break
            }
        }

        private static func applyNumericFacet(_ name: String?, _ value: String?, into facets: inout Facets) {
            let number = value.flatMap(Int.init)
            switch name {
            case "length": facets.length = number
            case "minLength": facets.minLength = number
            case "maxLength": facets.maxLength = number
            case "totalDigits": facets.totalDigits = number
            case "fractionDigits": facets.fractionDigits = number
            default: break
            }
        }

        private static func whiteSpace(_ value: String?) -> WhiteSpace? {
            switch value {
            case "preserve": .preserve
            case "replace": .replace
            case "collapse": .collapse
            default: nil
            }
        }

        // MARK: Complex types

        private static func complexType(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> ComplexType {
            let mixed = XSDNode.attribute(node, "mixed") == "true"
            var attributes = attributeUses(under: node, simpleTypes)
            if let simpleContent = XSDNode.firstChild(node, named: "simpleContent") {
                let inner = derivation(simpleContent)
                attributes += inner.map { attributeUses(under: $0, simpleTypes) } ?? []
                return ComplexType(attributes: attributes, content: .simpleContent(simpleContentType(simpleContent, simpleTypes)))
            }
            let container = XSDNode.firstChild(node, named: "complexContent").flatMap(derivation) ?? node
            attributes += container === node ? [] : attributeUses(under: container, simpleTypes)
            guard let particle = modelGroup(in: container, simpleTypes) else {
                return ComplexType(attributes: attributes, content: .empty)
            }
            return ComplexType(attributes: attributes, content: mixed ? .mixed(particle) : .elementOnly(particle))
        }

        private static func derivation(_ node: Tree) -> Tree? {
            XSDNode.firstChild(node, named: "restriction") ?? XSDNode.firstChild(node, named: "extension")
        }

        private static func simpleContentType(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> SimpleType {
            guard let inner = derivation(node) else { return SimpleType(base: .string) }
            let baseName = XSDNode.stripPrefix(XSDNode.attribute(inner, "base") ?? "string")
            let base = BuiltinType(rawValue: baseName) ?? simpleTypes[baseName]?.base ?? .string
            var facets = simpleTypes[baseName]?.facets ?? Facets()
            applyFacets(inner, into: &facets)
            return SimpleType(base: base, facets: facets)
        }

        private static func attributeUses(under node: Tree, _ simpleTypes: [String: SimpleType]) -> [AttributeUse] {
            XSDNode.children(node, named: "attribute").compactMap { attributeUse($0, simpleTypes) }
        }

        private static func attributeUse(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> AttributeUse? {
            guard let name = XSDNode.attribute(node, "name") else { return nil }
            let required = XSDNode.attribute(node, "use") == "required"
            let type: SimpleType = if let typeName = XSDNode.attribute(node, "type") {
                simpleTypeReference(typeName, simpleTypes)
            } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
                simpleType(inline, simpleTypes)
            } else {
                SimpleType(base: .string)
            }
            return AttributeUse(name: PureXML.Model.QualifiedName(name), type: type, required: required)
        }

        // MARK: Model groups

        private static func modelGroup(in node: Tree, _ simpleTypes: [String: SimpleType]) -> Particle? {
            for (name, compositor) in [("sequence", Compositor.sequence), ("choice", .choice), ("all", .all)] {
                if let group = XSDNode.firstChild(node, named: name) {
                    return groupParticle(group, compositor, simpleTypes)
                }
            }
            return nil
        }

        private static func groupParticle(
            _ node: Tree,
            _ compositor: Compositor,
            _ simpleTypes: [String: SimpleType],
        ) -> Particle {
            var particles: [Particle] = []
            for child in XSDNode.elementChildren(node) {
                if let member = particle(child, simpleTypes) { particles.append(member) }
            }
            let (minimum, maximum) = XSDNode.occurrence(node)
            return Particle(
                minOccurs: minimum,
                maxOccurs: maximum,
                term: .group(Group(compositor: compositor, particles: particles)),
            )
        }

        private static func particle(_ node: Tree, _ simpleTypes: [String: SimpleType]) -> Particle? {
            let (minimum, maximum) = XSDNode.occurrence(node)
            switch XSDNode.localName(node) {
            case "element":
                let name = XSDNode.attribute(node, "name") ?? XSDNode.stripPrefix(XSDNode.attribute(node, "ref") ?? "")
                let type = XSDNode.attribute(node, "name") != nil ? elementType(node, simpleTypes) : ElementType.complex(anyType)
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .element(name: PureXML.Model.QualifiedName(name), type: type))
            case "sequence":
                return groupParticle(node, .sequence, simpleTypes)
            case "choice":
                return groupParticle(node, .choice, simpleTypes)
            case "all":
                return groupParticle(node, .all, simpleTypes)
            case "any":
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .wildcard(Wildcard()))
            default:
                return nil
            }
        }
    }
}
