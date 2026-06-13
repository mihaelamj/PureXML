extension PureXML.Schema {
    /// Parses an XSD schema document into its global element declarations and its
    /// named-type table. Matches the schema vocabulary by local name, so the XML
    /// Schema namespace prefix may be anything. Supports global and local element
    /// declarations, named and inline simple and complex types, `sequence`,
    /// `choice`, and `all` model groups with occurrence, attribute uses, simple
    /// content, the full facet set, `list` and `union` simple types, named
    /// attribute groups and model groups, and element and group references.
    enum XSDParser {
        static func parse(_ xsd: String, loader: (String) -> String? = { _ in nil }) throws -> XSDCompiled {
            let root = try PureXML.parseTree(xsd)
            guard let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" }) else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            var visited: Set<String> = []
            let containers = XSDNode.collectContainers(schema, loader, &visited)
            let derivation = derivationTables(containers)
            // checkRedefine and checkAllGroups examine the raw schema source, the
            // schema-compilation analog of well-formedness, so they stay throws;
            // the model-level consistency checks (final, restriction subsets) are
            // Validation rules collected by Schema.Document.
            try checkRedefine(containers)
            try checkAllGroups(containers)
            var context = XSDContext(
                simpleTypes: [:],
                attributeGroups: indexByName(allChildren(containers, named: "attributeGroup")),
                groups: indexByName(allChildren(containers, named: "group")),
                targetNamespace: XSDNode.attribute(schema, "targetNamespace"),
                substitutions: filterSubstitutions(XSDNode.substitutionMembers(containers), derivation),
                abstractElements: derivation.abstractElements,
            )
            context.elementFormQualified = XSDNode.attribute(schema, "elementFormDefault") == "qualified"
            context.attributeFormQualified = XSDNode.attribute(schema, "attributeFormDefault") == "qualified"
            context.complexTypeNodes = indexByName(allChildren(containers, named: "complexType"))
            context.globalAttributes = indexByName(allChildren(containers, named: "attribute"))
            resolveSimpleTypes(allChildren(containers, named: "simpleType"), into: &context)
            var types: [String: ElementType] = context.simpleTypes.mapValues(ElementType.simple)
            for node in allChildren(containers, named: "complexType") {
                if let name = XSDNode.attribute(node, "name") {
                    types[name] = .complex(complexType(node, context))
                }
            }
            var elements: [String: ElementType] = [:]
            for node in allChildren(containers, named: "element") where XSDNode.attribute(node, "name") != nil {
                let name = XSDNode.attribute(node, "name") ?? ""
                let type = elementType(node, context)
                elements[name] = type
                // An `xs:element ref="name"` resolves to this declaration's type
                // through a reserved key (a colon keeps it out of the NCName-only
                // type namespace), letting forward and recursive refs resolve at
                // validation time.
                types[elementKey(name)] = type
            }
            let (nillable, elementConstraints) = elementMetadata(containers)
            return XSDCompiled(
                elements: elements,
                types: types,
                constraints: identityConstraints(containers),
                nillableElements: nillable,
                elementConstraints: elementConstraints,
                abstractTypes: derivation.abstractTypes,
                abstractElements: derivation.abstractElements,
                typeBlock: derivation.typeBlock,
                elementBlock: derivation.elementBlock,
                typeDerivation: derivation.typeDerivation,
                typeFinal: derivation.typeFinal,
                targetNamespace: context.targetNamespace,
            )
        }

        private static func allChildren(_ containers: [XSDTree], named name: String) -> [XSDTree] {
            containers.flatMap { XSDNode.children($0, named: name) }
        }

        /// Resolves the named simple types into `context` over repeated passes:
        /// named simple types may restrict or list one another regardless of
        /// document order, so each pass sees the types the previous one resolved. A
        /// dependency chain of length n settles in at most n passes.
        private static func resolveSimpleTypes(_ nodes: [XSDTree], into context: inout XSDContext) {
            let named = nodes.filter { XSDNode.attribute($0, "name") != nil }
            for _ in named.indices {
                for node in named {
                    if let name = XSDNode.attribute(node, "name") {
                        context.simpleTypes[name] = XSDSimpleParser.simpleType(node, context)
                    }
                }
            }
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
            if let item = XSDSimpleParser.listBuiltinItem(local) {
                return .simple(.list(item: SimpleType(base: item)))
            }
            return .typeReference(local)
        }

        private static var anyType: ComplexType {
            ComplexType(
                attributeWildcard: Wildcard(processContents: .skip),
                content: .mixed(Particle(minOccurs: 0, maxOccurs: nil, term: .wildcard(Wildcard(processContents: .skip)))),
            )
        }

        // MARK: Complex types

        static func complexType(_ node: XSDTree, _ context: XSDContext) -> ComplexType {
            let mixed = XSDNode.attribute(node, "mixed") == "true"
            let attributes = attributeUses(under: node, context)
            if let simpleContent = XSDNode.firstChild(node, named: "simpleContent") {
                let inner = derivation(simpleContent)
                let wildcard = inner.flatMap { attributeWildcard(under: $0, context) }
                let extra = inner.map { attributeUses(under: $0, context) } ?? []
                return ComplexType(attributes: attributes + extra, attributeWildcard: wildcard, content: .simpleContent(simpleContentType(simpleContent, context)))
            }
            if let complexContent = XSDNode.firstChild(node, named: "complexContent"), let inner = derivation(complexContent) {
                return complexContentType(inner, mixed: mixed || XSDNode.attribute(complexContent, "mixed") == "true", context)
            }
            let wildcard = attributeWildcard(under: node, context)
            guard let particle = modelGroup(in: node, context) else {
                return ComplexType(attributes: attributes, attributeWildcard: wildcard, content: .empty)
            }
            return ComplexType(attributes: attributes, attributeWildcard: wildcard, content: mixed ? .mixed(particle) : .elementOnly(particle))
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

        /// The `default` or `fixed` value constraint declared on an attribute or
        /// element node, if any (`fixed` takes precedence).
        static func valueConstraint(of node: XSDTree) -> ValueConstraint? {
            if let fixed = XSDNode.attribute(node, "fixed") { return .fixed(fixed) }
            if let value = XSDNode.attribute(node, "default") { return .default(value) }
            return nil
        }

        // MARK: Model groups

        static func modelGroup(in node: XSDTree, _ context: XSDContext) -> Particle? {
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
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .wildcard(wildcard(node, context)))
            default:
                return nil
            }
        }

        private static func elementParticle(_ node: XSDTree, _ minimum: Int, _ maximum: Int?, _ context: XSDContext) -> Particle {
            if let ref = XSDNode.attribute(node, "ref") {
                let name = XSDNode.stripPrefix(ref)
                // An abstract head may not appear itself, only its members; a
                // concrete head appears alongside them.
                let head = context.abstractElements.contains(name) ? [] : [name]
                let alternatives = head + (context.substitutions[name] ?? [])
                if alternatives.count == 1 {
                    return Particle(minOccurs: minimum, maxOccurs: maximum, term: elementReferenceTerm(alternatives[0], context))
                }
                // The reference admits its substitution-group members, so expand it
                // to a choice over the head and every member, each carrying its own
                // declared type.
                let members = alternatives.map { Particle(term: elementReferenceTerm($0, context)) }
                return Particle(minOccurs: minimum, maxOccurs: maximum, term: .group(Group(compositor: .choice, particles: members)))
            }
            let name = XSDNode.attribute(node, "name") ?? ""
            return Particle(
                minOccurs: minimum,
                maxOccurs: maximum,
                term: .element(name: localElementName(name, XSDNode.attribute(node, "form"), context), type: elementType(node, context)),
            )
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

extension PureXML.Schema.XSDParser {
    /// The qualified name of a reference to a global element: globals are always in
    /// the schema's target namespace.
    static func elementReferenceTerm(_ name: String, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.Term {
        .element(
            name: PureXML.Model.QualifiedName(localName: name, namespaceURI: context.targetNamespace),
            type: .typeReference(elementKey(name)),
        )
    }

    /// The qualified name of a local element declaration: in the target namespace
    /// when `elementFormDefault` (or the element's own `form`) is qualified,
    /// otherwise in no namespace.
    static func localElementName(_ name: String, _ form: String?, _ context: PureXML.Schema.XSDContext) -> PureXML.Model.QualifiedName {
        let qualified = form == "qualified" || (form == nil && context.elementFormQualified)
        return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
    }
}

extension PureXML.Schema.XSDParser {
    /// Gathers `nillable` and `default`/`fixed` value constraints from every
    /// element declaration at any depth, keyed by the element's name.
    static func elementMetadata(_ containers: [XSDTree]) -> (Set<String>, [String: PureXML.Schema.ValueConstraint]) {
        var nillable: Set<String> = []
        var constraints: [String: PureXML.Schema.ValueConstraint] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                guard let name = PureXML.Schema.XSDNode.attribute(element, "name") else { continue }
                if PureXML.Schema.XSDNode.attribute(element, "nillable") == "true" { nillable.insert(name) }
                if let constraint = valueConstraint(of: element) { constraints[name] = constraint }
            }
        }
        return (nillable, constraints)
    }

    /// Gathers identity constraints (`unique`, `key`, `keyref`) declared on any
    /// element at any depth, keyed by the element's name.
    static func identityConstraints(_ containers: [XSDTree]) -> [String: [PureXML.Schema.IdentityConstraint]] {
        var map: [String: [PureXML.Schema.IdentityConstraint]] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                guard let name = PureXML.Schema.XSDNode.attribute(element, "name") else { continue }
                let constraints = PureXML.Schema.XSDNode.elementChildren(element).compactMap(constraint)
                if !constraints.isEmpty { map[name, default: []] += constraints }
            }
        }
        return map
    }

    private static func constraint(_ node: XSDTree) -> PureXML.Schema.IdentityConstraint? {
        let kind: PureXML.Schema.IdentityConstraintKind
        switch PureXML.Schema.XSDNode.localName(node) {
        case "unique": kind = .unique
        case "key": kind = .key
        case "keyref": kind = .keyref(refer: PureXML.Schema.XSDNode.stripPrefix(PureXML.Schema.XSDNode.attribute(node, "refer") ?? ""))
        default: return nil
        }
        let selector = PureXML.Schema.XSDNode.firstChild(node, named: "selector").flatMap { PureXML.Schema.XSDNode.attribute($0, "xpath") } ?? ""
        let fields = PureXML.Schema.XSDNode.children(node, named: "field").compactMap { PureXML.Schema.XSDNode.attribute($0, "xpath") }
        return PureXML.Schema.IdentityConstraint(name: PureXML.Schema.XSDNode.attribute(node, "name") ?? "", kind: kind, selector: selector, fields: fields)
    }

    static func descendants(_ node: XSDTree, named name: String) -> [XSDTree] {
        var result: [XSDTree] = []
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            if PureXML.Schema.XSDNode.localName(child) == name { result.append(child) }
            result += descendants(child, named: name)
        }
        return result
    }
}
