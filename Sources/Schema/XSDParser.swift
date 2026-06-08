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

/// The parsing context: the named simple types resolved so far, plus the
/// definition nodes for named attribute groups and model groups (so their refs
/// can be expanded), and a guard against cyclic group references. File-scope and
/// private.
private struct Context {
    var simpleTypes: [String: PureXML.Schema.SimpleType]
    var attributeGroups: [String: Tree]
    var groups: [String: Tree]
    var visitingGroups: Set<String> = []

    func visiting(_ group: String) -> Context {
        var copy = self
        copy.visitingGroups.insert(group)
        return copy
    }
}

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
        ) throws -> (elements: [String: ElementType], types: [String: ElementType]) {
            let root = try PureXML.parseTree(xsd)
            guard let schema = XSDNode.elementChildren(root).first(where: { XSDNode.localName($0) == "schema" }) else {
                throw PureXML.Schema.SchemaError.notASchema
            }
            var context = Context(
                simpleTypes: [:],
                attributeGroups: indexByName(XSDNode.children(schema, named: "attributeGroup")),
                groups: indexByName(XSDNode.children(schema, named: "group")),
            )
            // Named simple types may restrict or list one another regardless of
            // document order, so resolve them over repeated passes: each pass sees
            // the types resolved by the previous one. A chain of length n settles
            // in at most n passes.
            let simpleNodes = XSDNode.children(schema, named: "simpleType").filter { XSDNode.attribute($0, "name") != nil }
            for _ in simpleNodes.indices {
                for node in simpleNodes {
                    if let name = XSDNode.attribute(node, "name") {
                        context.simpleTypes[name] = XSDSimpleParser.simpleType(node, context)
                    }
                }
            }
            var types: [String: ElementType] = context.simpleTypes.mapValues(ElementType.simple)
            for node in XSDNode.children(schema, named: "complexType") {
                if let name = XSDNode.attribute(node, "name") {
                    types[name] = .complex(complexType(node, context))
                }
            }
            var elements: [String: ElementType] = [:]
            for node in XSDNode.children(schema, named: "element") {
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

        static func elementKey(_ name: String) -> String {
            "element:\(name)"
        }

        private static func indexByName(_ nodes: [Tree]) -> [String: Tree] {
            var index: [String: Tree] = [:]
            for node in nodes {
                if let name = XSDNode.attribute(node, "name") { index[name] = node }
            }
            return index
        }

        // MARK: Element and type references

        private static func elementType(_ node: Tree, _ context: Context) -> ElementType {
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

        private static func complexType(_ node: Tree, _ context: Context) -> ComplexType {
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

        private static func derivation(_ node: Tree) -> Tree? {
            XSDNode.firstChild(node, named: "restriction") ?? XSDNode.firstChild(node, named: "extension")
        }

        private static func simpleContentType(_ node: Tree, _ context: Context) -> SimpleType {
            guard let inner = derivation(node) else { return SimpleType(base: .string) }
            let baseName = XSDNode.stripPrefix(XSDNode.attribute(inner, "base") ?? "string")
            let base = BuiltinType(rawValue: baseName) ?? context.simpleTypes[baseName]?.base ?? .string
            var facets = context.simpleTypes[baseName]?.facets ?? Facets()
            XSDSimpleParser.applyFacets(inner, into: &facets)
            return SimpleType(base: base, facets: facets)
        }

        // MARK: Attribute uses and groups

        private static func attributeUses(under node: Tree, _ context: Context, visited: Set<String> = []) -> [AttributeUse] {
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

        private static func attributeUse(_ node: Tree, _ context: Context) -> AttributeUse? {
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

        private static func modelGroup(in node: Tree, _ context: Context) -> Particle? {
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
            _ node: Tree,
            _ compositor: Compositor,
            _ context: Context,
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

        private static func particle(_ node: Tree, _ context: Context) -> Particle? {
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

        private static func elementParticle(_ node: Tree, _ minimum: Int, _ maximum: Int?, _ context: Context) -> Particle {
            if let ref = XSDNode.attribute(node, "ref") {
                let name = XSDNode.stripPrefix(ref)
                return Particle(
                    minOccurs: minimum,
                    maxOccurs: maximum,
                    term: .element(name: PureXML.Model.QualifiedName(name), type: .typeReference(elementKey(name))),
                )
            }
            let name = XSDNode.attribute(node, "name") ?? ""
            return Particle(
                minOccurs: minimum,
                maxOccurs: maximum,
                term: .element(name: PureXML.Model.QualifiedName(name), type: elementType(node, context)),
            )
        }

        private static func groupReferenceParticle(_ node: Tree, _ minimum: Int, _ maximum: Int?, _ context: Context) -> Particle? {
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

    /// Parses XSD simple types: atomic restrictions with the full facet set, and
    /// the `list` and `union` varieties. Kept beside ``XSDParser`` so the two
    /// share the file-scope tree helpers and parsing context.
    enum XSDSimpleParser {
        fileprivate static func simpleType(_ node: Tree, _ context: Context) -> SimpleType {
            if let list = XSDNode.firstChild(node, named: "list") {
                return listType(list, context)
            }
            if let union = XSDNode.firstChild(node, named: "union") {
                return unionType(union, context)
            }
            guard let restriction = XSDNode.firstChild(node, named: "restriction") else {
                return SimpleType(base: .string)
            }
            let baseName = XSDNode.stripPrefix(XSDNode.attribute(restriction, "base") ?? "string")
            var base = BuiltinType.string
            var facets = Facets()
            var variety = Variety.atomic
            if let builtin = BuiltinType(rawValue: baseName) {
                base = builtin
            } else if let parent = context.simpleTypes[baseName] {
                base = parent.base
                facets = parent.facets
                variety = parent.variety
            }
            applyFacets(restriction, into: &facets)
            return SimpleType(base: base, facets: facets, variety: variety)
        }

        fileprivate static func simpleTypeReference(_ typeName: String, _ context: Context) -> SimpleType {
            let local = XSDNode.stripPrefix(typeName)
            if let builtin = BuiltinType(rawValue: local) { return SimpleType(base: builtin) }
            return context.simpleTypes[local] ?? SimpleType(base: .string)
        }

        fileprivate static func applyFacets(_ restriction: Tree, into facets: inout Facets) {
            for facet in XSDNode.elementChildren(restriction) {
                let value = XSDNode.attribute(facet, "value")
                applyStringFacet(XSDNode.localName(facet), value, into: &facets)
                applyNumericFacet(XSDNode.localName(facet), value, into: &facets)
            }
        }

        private static func listType(_ node: Tree, _ context: Context) -> SimpleType {
            let item: SimpleType = if let itemType = XSDNode.attribute(node, "itemType") {
                simpleTypeReference(itemType, context)
            } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
                simpleType(inline, context)
            } else {
                SimpleType(base: .string)
            }
            return .list(item: item)
        }

        private static func unionType(_ node: Tree, _ context: Context) -> SimpleType {
            var members: [SimpleType] = []
            if let names = XSDNode.attribute(node, "memberTypes") {
                members += names.split(whereSeparator: \.isWhitespace).map { simpleTypeReference(String($0), context) }
            }
            members += XSDNode.children(node, named: "simpleType").map { simpleType($0, context) }
            return .union(members)
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
    }
}
