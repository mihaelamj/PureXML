private typealias XSDNode = PureXML.Schema.XSDNode
private typealias XSDContext = PureXML.Schema.XSDContext
private typealias Particle = PureXML.Schema.Particle
private typealias Compositor = PureXML.Schema.Compositor
private typealias Group = PureXML.Schema.Group
private typealias ElementType = PureXML.Schema.ElementType

extension PureXML.Schema.XSDParser {
    // MARK: Model groups

    static func modelGroup(in node: PureXML.Model.TreeNode, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.Particle? {
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
        _ node: PureXML.Model.TreeNode,
        _ compositor: Compositor,
        _ context: XSDContext,
    ) -> Particle {
        var particles: [Particle] = []
        for child in XSDNode.elementChildren(node) {
            if let member = particle(child, context) { particles.append(member) }
        }
        let (minimum, maximum) = XSDNode.occurrence(node)
        if compositor == .all, minimum == 0 {
            particles = particles.map { Particle(minOccurs: 0, maxOccurs: $0.maxOccurs, term: $0.term) }
        }
        return Particle(
            minOccurs: minimum,
            maxOccurs: maximum,
            term: .group(Group(compositor: compositor, particles: particles)),
        )
    }

    private static func particle(_ node: PureXML.Model.TreeNode, _ context: XSDContext) -> Particle? {
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

    private static func elementParticle(_ node: PureXML.Model.TreeNode, _ minimum: Int, _ maximum: Int?, _ context: XSDContext) -> Particle {
        if let ref = XSDNode.attribute(node, "ref") {
            return referenceParticle(ref, minimum, maximum, context, node: node)
        }
        let name = XSDNode.attribute(node, "name") ?? ""
        return Particle(
            minOccurs: minimum,
            maxOccurs: maximum,
            term: .element(
                name: localElementName(name, XSDNode.attribute(node, "form"), context),
                type: elementType(node, context),
                typeName: elementTypeName(node),
                valueConstraint: valueConstraint(of: node),
                block: methodSet(XSDNode.attribute(node, "block") ?? context.blockDefault),
                nillable: ["true", "1"].contains(XSDNode.attribute(node, "nillable")),
            ),
        )
    }

    private static func groupReferenceParticle(_ node: PureXML.Model.TreeNode, _ minimum: Int, _ maximum: Int?, _ context: XSDContext) -> Particle? {
        guard let ref = XSDNode.attribute(node, "ref") else { return nil }
        let name = XSDNode.stripPrefix(ref)
        if context.visitingGroups.contains(name) {
            guard context.redefinedGroups.contains(name),
                  let base = context.baseGroups[name]
            else {
                return nil
            }
            let scoped = context.scoped(for: XSDNode.schemaOwner(base))
            guard let inner = modelGroup(in: base, scoped.visiting(name)) else {
                return nil
            }
            return Particle(minOccurs: minimum, maxOccurs: maximum, term: inner.term)
        }
        guard let definition = context.groups[name] else {
            return nil
        }
        let scoped = context.scoped(for: XSDNode.schemaOwner(definition))
        guard let inner = modelGroup(in: definition, scoped.visiting(name)) else {
            return nil
        }
        return Particle(minOccurs: minimum, maxOccurs: maximum, term: inner.term)
    }

    /// The particle for an `<xs:element ref="...">`. An abstract head may not appear
    /// itself, only its substitution-group members; a concrete head appears alongside
    /// them, the reference expanding to a choice over the head and every member.
    static func referenceParticle(
        _ ref: String,
        _ minimum: Int,
        _ maximum: Int?,
        _ context: PureXML.Schema.XSDContext,
        node: XSDTree? = nil,
    ) -> PureXML.Schema.Particle {
        let name = PureXML.Schema.XSDNode.stripPrefix(ref)
        let bindings = node.map { PureXML.Schema.XSDParser.namespaceBindingsInScope(of: $0, defaultBindings: context.namespaceBindings) }
            ?? context.namespaceBindings
        let refNamespace = PureXML.Schema.XSDNode.referenceNamespace(ref, bindings)
        let head: [(String, String?)] = context.abstractElements.contains(name) ? [] : [(name, refNamespace)]
        let alternatives = head + (context.substitutions[name] ?? []).map { ($0, context.elementNamespaces[$0] ?? context.targetNamespace) }
        if alternatives.count == 1 {
            return PureXML.Schema.Particle(minOccurs: minimum, maxOccurs: maximum, term: elementReferenceTerm(alternatives[0].0, alternatives[0].1))
        }
        let members = alternatives.map { PureXML.Schema.Particle(term: elementReferenceTerm($0.0, $0.1)) }
        return PureXML.Schema.Particle(minOccurs: minimum, maxOccurs: maximum, term: .group(.init(compositor: .choice, particles: members)))
    }

    /// The term for a reference to a global element, in the resolved `namespace`.
    static func elementReferenceTerm(_ name: String, _ namespace: String?) -> PureXML.Schema.Term {
        .element(
            name: PureXML.Model.QualifiedName(localName: name, namespaceURI: namespace),
            type: .typeReference(elementKey(name)),
            typeName: nil,
            valueConstraint: nil,
        )
    }
}
