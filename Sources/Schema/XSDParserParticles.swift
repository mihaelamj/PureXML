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
        let occurrence = XSDNode.occurrenceRange(node)
        // An `all` group's own `minOccurs="0"` makes the GROUP optional (it occurs
        // zero or one times), not its members optional: when the group is present
        // (any child appears) every member keeps its own `minOccurs`. The members
        // therefore retain their declared occurrence here; the absent-group case is
        // handled at validation time (see allStructureErrors) by skipping the
        // required-member check only when the group has no children at all.
        return Particle(
            occurrenceRange: occurrence,
            term: .group(Group(compositor: compositor, particles: particles)),
        )
    }

    private static func particle(_ node: PureXML.Model.TreeNode, _ context: XSDContext) -> Particle? {
        let occurrence = XSDNode.occurrenceRange(node)
        switch XSDNode.localName(node) {
        case "element":
            return elementParticle(node, occurrence, context)
        case "sequence":
            return groupParticle(node, .sequence, context)
        case "choice":
            return groupParticle(node, .choice, context)
        case "all":
            return groupParticle(node, .all, context)
        case "group":
            return groupReferenceParticle(node, occurrence, context)
        case "any":
            return Particle(occurrenceRange: occurrence, term: .wildcard(wildcard(node, context)))
        default:
            return nil
        }
    }

    private static func elementParticle(_ node: PureXML.Model.TreeNode, _ occurrence: PureXML.Schema.OccurrenceRange, _ context: XSDContext) -> Particle {
        if let ref = XSDNode.attribute(node, "ref") {
            return referenceParticle(ref, occurrence, context, node: node)
        }
        let name = XSDNode.attribute(node, "name") ?? ""
        return Particle(
            occurrenceRange: occurrence,
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

    private static func groupReferenceParticle(_ node: PureXML.Model.TreeNode, _ occurrence: PureXML.Schema.OccurrenceRange, _ context: XSDContext) -> Particle? {
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
            return Particle(occurrenceRange: occurrence, term: inner.term)
        }
        guard let definition = context.groups[name] else {
            return nil
        }
        let scoped = context.scoped(for: XSDNode.schemaOwner(definition))
        guard let inner = modelGroup(in: definition, scoped.visiting(name)) else {
            return nil
        }
        return Particle(occurrenceRange: occurrence, term: inner.term)
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
        referenceParticle(ref, .init(minimum: minimum, maximum: maximum), context, node: node)
    }

    static func referenceParticle(
        _ ref: String,
        _ occurrence: PureXML.Schema.OccurrenceRange,
        _ context: PureXML.Schema.XSDContext,
        node: XSDTree? = nil,
    ) -> PureXML.Schema.Particle {
        let name = PureXML.Schema.XSDNode.stripPrefix(ref)
        let bindings = node.map { PureXML.Schema.XSDParser.namespaceBindingsInScope(of: $0, defaultBindings: context.namespaceBindings) }
            ?? context.namespaceBindings
        let refNamespace = PureXML.Schema.XSDNode.referenceNamespace(ref, bindings)
        let headKey = PureXML.Schema.XSDParser.derivationKey(name, in: refNamespace)
        let head: [(String, String?)] = context.abstractElements.contains(name) ? [] : [(name, refNamespace)]
        // Members are namespaced keys (`{ns}local`): unpack each to its local name
        // and namespace so the choice over the head and its members keeps every
        // member's own namespace, even across imported namespaces.
        let alternatives = head + (context.substitutions[headKey] ?? []).map { PureXML.Schema.XSDParser.unpackElementName($0) }
        if alternatives.count == 1 {
            return PureXML.Schema.Particle(occurrenceRange: occurrence, term: elementReferenceTerm(alternatives[0].0, alternatives[0].1, context))
        }
        let members = alternatives.map { PureXML.Schema.Particle(term: elementReferenceTerm($0.0, $0.1, context)) }
        return PureXML.Schema.Particle(occurrenceRange: occurrence, term: .group(.init(compositor: .choice, particles: members)))
    }

    /// The term for a reference to a global element, in the resolved `namespace`.
    static func elementReferenceTerm(_ name: String, _ namespace: String?, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.Term {
        let definition = context.globalElements[derivationKey(name, in: namespace)]
        return .element(
            name: PureXML.Model.QualifiedName(localName: name, namespaceURI: namespace),
            type: .typeReference(elementKey(name)),
            typeName: definition.flatMap(elementTypeName),
            valueConstraint: definition.flatMap(valueConstraint),
            block: definition.map { blockMethods(of: $0, admitting: [.extension, .restriction, .substitution]) } ?? [],
            nillable: definition.map { ["true", "1"].contains(XSDNode.attribute($0, "nillable")) } ?? false,
        )
    }
}
