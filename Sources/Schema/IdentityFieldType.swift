extension PureXML.Schema.IdentityValidator {
    /// Whether the field's DECLARED target is a complex type with non-simple content
    /// (empty or element-only/mixed), which is not a valid identity field even when its
    /// instance node has no element children (an attributes-only element, XSTS idG006).
    /// Resolved through the schema type model: the selector target's type is looked up,
    /// the field's same-named child element found in its content model, and its declared
    /// type classified. A simple/simpleContent type, a type reached only through a
    /// reference, a complex field path, or an unresolvable target is left alone, so no
    /// valid field is rejected (cvc-identity-constraint.3 / c-fields-xpaths).
    func fieldTargetIsComplexNonSimple(_ field: String, at target: PureXML.Model.TreeNode) -> Bool {
        guard !field.contains(where: { "@/[(.".contains($0) }), let targetName = target.name,
              case let .complex(targetComplex)? = declaredType(of: targetName),
              let fieldType = childElementType(named: field, in: targetComplex.content),
              case let .complex(fieldComplex) = fieldType
        else { return false }
        if case .simpleContent = fieldComplex.content { return false }
        return true
    }

    /// The declared `ElementType` of a global element, by namespaced or local key.
    private func declaredType(of name: PureXML.Model.QualifiedName) -> PureXML.Schema.ElementType? {
        types[PureXML.Schema.XSDParser.elementDeclarationKey(name)] ?? types[PureXML.Schema.XSDParser.elementKey(name.localName)]
    }

    /// The declared type of the first element named `local` directly within a content
    /// model (descending through model groups), or nil when none matches.
    private func childElementType(named local: String, in content: PureXML.Schema.ContentType) -> PureXML.Schema.ElementType? {
        switch content {
        case let .elementOnly(particle), let .mixed(particle): childElementType(named: local, in: particle)
        default: nil
        }
    }

    private func childElementType(named local: String, in particle: PureXML.Schema.Particle) -> PureXML.Schema.ElementType? {
        switch particle.term {
        case let .element(name, type, _, _, _, _):
            name.localName == local ? type : nil
        case let .group(group):
            group.particles.lazy.compactMap { childElementType(named: local, in: $0) }.first
        case .wildcard:
            nil
        }
    }
}
