private typealias XSDComplexType = PureXML.Schema.ComplexType
private typealias XSDContentType = PureXML.Schema.ContentType
private typealias XSDParticle = PureXML.Schema.Particle
private typealias XSDGroup = PureXML.Schema.Group
private typealias XSDContentNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// Builds the effective complex type of a `complexContent` derivation. An
    /// extension composes the base type's attributes and content with its own
    /// (the base's content first, then the extension's, in sequence); a
    /// restriction states the full restricted model and replaces the base.
    ///
    /// Note: a restriction's model is taken as given. It is NOT verified to be a
    /// structurally valid subset of the base ("Particle Valid (Restriction)" in
    /// XSD 1.0), which is a much larger algorithm; an unfaithful restriction is
    /// accepted.
    static func complexContentType(_ derivationNode: XSDTree, mixed: Bool, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.ComplexType {
        let ownAttributes = attributeUses(under: derivationNode, context)
        let ownWildcard = attributeWildcard(under: derivationNode, context)
        let ownParticle = modelGroup(in: derivationNode, context)
        let derivationType = XSDContentNode.localName(derivationNode)

        if derivationType == "extension", let base = resolvedBase(derivationNode, context) {
            return XSDComplexType(
                attributes: base.attributes + ownAttributes,
                attributeWildcard: ownWildcard ?? base.attributeWildcard,
                content: extendedContent(base: base.content, own: ownParticle, mixed: mixed),
            )
        } else if derivationType == "restriction" {
            let allowedOwnAttributes = ownAttributes.filter { !isProhibited($0.name, under: derivationNode, context) }
            let finalAttributes: [PureXML.Schema.AttributeUse]
            if let base = resolvedBase(derivationNode, context) {
                var attributes: [PureXML.Schema.AttributeUse] = []
                for baseAttr in base.attributes {
                    if isProhibited(baseAttr.name, under: derivationNode, context) {
                        continue
                    }
                    if let derived = allowedOwnAttributes.first(where: { $0.name == baseAttr.name }) {
                        attributes.append(derived)
                    } else {
                        attributes.append(baseAttr)
                    }
                }
                for ownAttr in allowedOwnAttributes {
                    guard !base.attributes.contains(where: { $0.name == ownAttr.name }) else { continue }
                    attributes.append(ownAttr)
                }
                finalAttributes = attributes
            } else {
                finalAttributes = allowedOwnAttributes
            }
            return XSDComplexType(
                attributes: finalAttributes,
                attributeWildcard: ownWildcard,
                content: content(ownParticle, mixed: mixed),
            )
        }

        return XSDComplexType(
            attributes: ownAttributes,
            attributeWildcard: ownWildcard,
            content: content(ownParticle, mixed: mixed),
        )
    }

    private static func isProhibited(_ name: PureXML.Model.QualifiedName, under node: XSDTree, _ context: PureXML.Schema.XSDContext, visited: Set<String> = []) -> Bool {
        for child in XSDContentNode.elementChildren(node) {
            switch XSDContentNode.localName(child) {
            case "attribute":
                if let attrName = attributeName(child, context), attrName == name {
                    if XSDContentNode.attribute(child, "use") == "prohibited" {
                        return true
                    }
                }
            case "attributeGroup":
                guard let ref = XSDContentNode.attribute(child, "ref") else { break }
                let refName = XSDContentNode.stripPrefix(ref)
                guard !visited.contains(refName), let group = context.attributeGroups[refName] else { break }
                if isProhibited(name, under: group, context, visited: visited.union([refName])) {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private static func attributeName(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Model.QualifiedName? {
        if let ref = XSDContentNode.attribute(node, "ref") {
            let refName = XSDContentNode.stripPrefix(ref)
            let namespace = XSDContentNode.referenceNamespace(ref, context.namespaceBindings)
            return PureXML.Model.QualifiedName(localName: refName, namespaceURI: namespace)
        }
        guard let name = XSDContentNode.attribute(node, "name") else { return nil }
        let qualified = XSDContentNode.attribute(node, "form") == "qualified"
            || (XSDContentNode.attribute(node, "form") == nil && context.attributeFormQualified)
        return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
    }

    /// The base complex type a derivation extends, parsed from its definition
    /// node, or nil when the base is unknown (a built-in or undeclared type) or
    /// would form a derivation cycle.
    private static func resolvedBase(_ derivationNode: XSDTree, _ context: PureXML.Schema.XSDContext) -> XSDComplexType? {
        guard let baseName = XSDContentNode.attribute(derivationNode, "base").map(XSDContentNode.stripPrefix),
              !context.visitingTypes.contains(baseName), let baseNode = context.complexTypeNodes[baseName]
        else {
            return nil
        }
        return complexType(baseNode, context.visitingType(baseName))
    }

    /// A particle wrapped as element-only or mixed content, or empty content when
    /// there is no particle.
    private static func content(_ particle: XSDParticle?, mixed: Bool) -> XSDContentType {
        guard let particle else { return mixed ? .mixed(emptyParticle) : .empty }
        return mixed ? .mixed(particle) : .elementOnly(particle)
    }

    /// The content of an extension: the base content's particle followed by the
    /// extension's own particle, in a sequence. Mixed if either side is mixed.
    private static func extendedContent(base: XSDContentType, own: XSDParticle?, mixed: Bool) -> XSDContentType {
        let baseMixed = if case .mixed = base { true } else { false }
        let combined = combine(particle(of: base), own)
        return content(combined, mixed: mixed || baseMixed)
    }

    private static func particle(of content: XSDContentType) -> XSDParticle? {
        switch content {
        case let .elementOnly(particle), let .mixed(particle): particle
        case .empty, .simpleContent: nil
        }
    }

    private static func combine(_ first: XSDParticle?, _ second: XSDParticle?) -> XSDParticle? {
        switch (first, second) {
        case let (first?, second?):
            XSDParticle(term: .group(XSDGroup(compositor: .sequence, particles: [first, second])))
        case let (first?, nil): first
        case let (nil, second): second
        }
    }

    private static var emptyParticle: XSDParticle {
        XSDParticle(minOccurs: 0, maxOccurs: 1, term: .group(XSDGroup(compositor: .sequence, particles: [])))
    }
}
