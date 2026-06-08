extension PureXML.Schema {
    /// Parses an XSD schema document into its global element declarations and its
    /// named-type table. Matches the schema vocabulary by local name, so the XML
    /// Schema namespace prefix may be anything. Supports global and local element
    /// declarations, named and inline simple and complex types, `sequence`,
    /// `choice`, and `all` model groups with occurrence, attribute uses, simple
    /// content, the full facet set, `list` and `union` simple types, named
    /// attribute groups and model groups, and element and group references.
    enum XSDParser {
        static func parse(
            _ xsd: String,
            loader: (String) -> String? = { _ in nil },
        ) throws -> (elements: [String: ElementType], types: [String: ElementType]) {
            let root = try PureXML.parseTree(xsd)
            guard let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" }) else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            var visited: Set<String> = []
            let containers = XSDNode.collectContainers(schema, loader, &visited)
            var context = XSDContext(
                simpleTypes: [:],
                attributeGroups: indexByName(allChildren(containers, named: "attributeGroup")),
                groups: indexByName(allChildren(containers, named: "group")),
                substitutions: XSDNode.substitutionMembers(containers),
            )
            // Named simple types may restrict or list one another regardless of
            // document order, so resolve them over repeated passes: each pass sees
            // the types resolved by the previous one. A chain of length n settles
            // in at most n passes.
            let simpleNodes = allChildren(containers, named: "simpleType").filter { XSDNode.attribute($0, "name") != nil }
            for _ in simpleNodes.indices {
                for node in simpleNodes {
                    if let name = XSDNode.attribute(node, "name") {
                        context.simpleTypes[name] = XSDSimpleParser.simpleType(node, context)
                    }
                }
            }
            var types: [String: ElementType] = context.simpleTypes.mapValues(ElementType.simple)
            for node in allChildren(containers, named: "complexType") {
                if let name = XSDNode.attribute(node, "name") {
                    types[name] = .complex(complexType(node, context))
                }
            }
            var elements: [String: ElementType] = [:]
            for node in allChildren(containers, named: "element") {
                if let name = XSDNode.attribute(node, "name") {
                    let type = elementType(node, context)
                    elements[name] = type
                    // An `xs:element ref="name"` resolves to this declaration's type
                    // through a reserved key (a colon keeps it out of the NCName-only
                    // type namespace), letting forward and recursive refs resolve at
                    // validation time.
                    types[elementKey(name)] = type
                }
            }
            return (elements, types)
        }

        private static func allChildren(_ containers: [XSDTree], named name: String) -> [XSDTree] {
            containers.flatMap { XSDNode.children($0, named: name) }
        }

        static func elementKey(_ name: String) -> String {
            "element:\(name)"
        }

        private static func indexByName(_ nodes: [XSDTree]) -> [String: XSDTree] {
            var index: [String: XSDTree] = [:]
            for node in nodes {
                if let name = XSDNode.attribute(node, "name") { index[name] = node }
            }
            return index
        }

        // MARK: Element and type references

        private static func elementType(_ node: XSDTree, _ context: XSDContext) -> ElementType {
            if let typeName = XSDNode.attribute(node, "type") {
                return typeReference(typeName)
            }
            if let inline = XSDNode.firstChild(node, named: "simpleType") {
                return .simple(XSDSimpleParser.simpleType(inline, context))
            }
            if let inline = XSDNode.firstChild(node, named: "complexType") {
                return .complex(complexType(inline, context))
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

        private static var anyType: ComplexType {
            ComplexType(
                allowsOtherAttributes: true,
                content: .mixed(Particle(minOccurs: 0, maxOccurs: nil, term: .wildcard(Wildcard()))),
            )
        }

        // MARK: Complex types

        private static func complexType(_ node: XSDTree, _ context: XSDContext) -> ComplexType {
            let mixed = XSDNode.attribute(node, "mixed") == "true"
            var attributes = attributeUses(under: node, context)
            if let simpleContent = XSDNode.firstChild(node, named: "simpleContent") {
                let inner = derivation(simpleContent)
                attributes += inner.map { attributeUses(under: $0, context) } ?? []
                return ComplexType(attributes: attributes, content: .simpleContent(simpleContentType(simpleContent, context)))
            }
            let container = XSDNode.firstChild(node, named: "complexContent").flatMap(derivation) ?? node
            attributes += container === node ? [] : attributeUses(under: container, context)
            guard let particle = modelGroup(in: container, context) else {
                return ComplexType(attributes: attributes, content: .empty)
            }
            return ComplexType(attributes: attributes, content: mixed ? .mixed(particle) : .elementOnly(particle))
        }

        private static func derivation(_ node: XSDTree) -> XSDTree? {
            XSDNode.firstChild(node, named: "restriction") ?? XSDNode.firstChild(node, named: "extension")
        }

        private static func simpleContentType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            guard let inner = derivation(node) else { return SimpleType(base: .string) }
            let baseName = XSDNode.stripPrefix(XSDNode.attribute(inner, "base") ?? "string")
            let base = BuiltinType(rawValue: baseName) ?? context.simpleTypes[baseName]?.base ?? .string
            var facets = context.simpleTypes[baseName]?.facets ?? Facets()
            XSDSimpleParser.applyFacets(inner, into: &facets)
            return SimpleType(base: base, facets: facets)
        }

        // MARK: Attribute uses and groups

        private static func attributeUses(under node: XSDTree, _ context: XSDContext, visited: Set<String> = []) -> [AttributeUse] {
            var uses: [AttributeUse] = []
            for child in XSDNode.elementChildren(node) {
                switch XSDNode.localName(child) {
                case "attribute":
                    if let use = attributeUse(child, context) { uses.append(use) }
                case "attributeGroup":
                    guard let ref = XSDNode.attribute(child, "ref") else { break }
                    let name = XSDNode.stripPrefix(ref)
                    guard !visited.contains(name), let group = context.attributeGroups[name] else { break }
                    uses += attributeUses(under: group, context, visited: visited.union([name]))
                default:
                    break
                }
            }
            return uses
        }

        private static func attributeUse(_ node: XSDTree, _ context: XSDContext) -> AttributeUse? {
            guard let name = XSDNode.attribute(node, "name") else { return nil }
            let required = XSDNode.attribute(node, "use") == "required"
            let type: SimpleType = if let typeName = XSDNode.attribute(node, "type") {
                XSDSimpleParser.simpleTypeReference(typeName, context)
            } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
                XSDSimpleParser.simpleType(inline, context)
            } else {
                SimpleType(base: .string)
            }
            return AttributeUse(name: PureXML.Model.QualifiedName(name), type: type, required: required)
        }

        // MARK: Model groups

        private static func modelGroup(in node: XSDTree, _ context: XSDContext) -> Particle? {
            for (name, compositor) in [("sequence", Compositor.sequence), ("choice", .choice), ("all", .all)] {
                if let group = XSDNode.firstChild(node, named: name) {
                    return groupParticle(group, compositor, context)
                }
            }
            if let groupRef = XSDNode.firstChild(node, named: "group") {
                return particle(groupRef, context)
            }
            return nil
        }

        private static func groupParticle(
            _ node: XSDTree,
            _ compositor: Compositor,
            _ context: XSDContext,
        ) -> Particle {
            var particles: [Particle] = []
            for child in XSDNode.elementChildren(node) {
                if let member = particle(child, context) { particles.append(member) }
            }
            let (minimum, maximum) = XSDNode.occurrence(node)
            return Particle(
                minOccurs: minimum,
                maxOccurs: maximum,
                term: .group(Group(compositor: compositor, particles: particles)),
            )
        }

        private static func particle(_ node: XSDTree, _ context: XSDContext) -> Particle? {
            let (minimum, maximum) = XSDNode.occurrence(node)
            switch XSDNode.localName(node) {
            case "element":
                return elementParticle(node, minimum, maximum, context)
            case "sequence":
                return groupParticle(node, .sequence, context)
            case "choice":
                return groupParticle(node, .choice, context)
            case "all":
                return groupParticle(node, .all, context)
            case "group":
                return groupReferenceParticle(node, minimum, maximum, context)
            case "any":
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .wildcard(Wildcard()))
            default:
                return nil
            }
        }

        private static func elementParticle(_ node: XSDTree, _ minimum: Int, _ maximum: Int?, _ context: XSDContext) -> Particle {
            if let ref = XSDNode.attribute(node, "ref") {
                let name = XSDNode.stripPrefix(ref)
                let alternatives = [name] + (context.substitutions[name] ?? [])
                if alternatives.count == 1 {
                    return Particle(minOccurs: minimum, maxOccurs: maximum, term: elementReferenceTerm(name))
                }
                // The reference admits its substitution-group members, so expand it
                // to a choice over the head and every member, each carrying its own
                // declared type.
                let members = alternatives.map { Particle(term: elementReferenceTerm($0)) }
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .group(Group(compositor: .choice, particles: members)))
            }
            let name = XSDNode.attribute(node, "name") ?? ""
            return Particle(
                minOccurs: minimum,
                maxOccurs: maximum,
                term: .element(name: PureXML.Model.QualifiedName(name), type: elementType(node, context)),
            )
        }

        private static func elementReferenceTerm(_ name: String) -> Term {
            .element(name: PureXML.Model.QualifiedName(name), type: .typeReference(elementKey(name)))
        }

        private static func groupReferenceParticle(_ node: XSDTree, _ minimum: Int, _ maximum: Int?, _ context: XSDContext) -> Particle? {
            guard let ref = XSDNode.attribute(node, "ref") else { return nil }
            let name = XSDNode.stripPrefix(ref)
            guard !context.visitingGroups.contains(name), let definition = context.groups[name],
                  let inner = modelGroup(in: definition, context.visiting(name))
            else {
                return nil
            }
            return Particle(minOccurs: minimum, maxOccurs: maximum, term: inner.term)
        }
    }
}
