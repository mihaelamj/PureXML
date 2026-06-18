extension PureXML.Schema.ComplexValidator {
    /// The first `xsi:type` override error for `child`, if any: a substitution
    /// blocked by `block`, a substitute not validly derived from the declared type
    /// (cvc-elt.4.3.2.1), or a missing `xsi:type` on an abstract declared type.
    func xsiTypeOverrideError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        if let blocked = blockedSubstitutionError(declared: declared, child: child, at: path) { return blocked }
        if let notDerived = notDerivedSubstitutionError(declared: declared, child: child, at: path) { return notDerived }
        if case let .typeReference(name) = declared { return abstractTypeError(named: name, child: child, at: path) }
        return nil
    }

    /// The error when an element's declared type is an abstract complex type and
    /// the element supplies no `xsi:type` to name a concrete derived type. An
    /// abstract type cannot itself be the type of an instance element.
    func abstractTypeError(
        named name: String,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard abstractTypes.contains(PureXML.Schema.XSDParser.bareTypeLocalName(name)),
              Self.xsiTypeName(child) == nil
        else { return nil }
        let bare = PureXML.Schema.XSDParser.bareTypeLocalName(name)
        return PureXML.Validation.ValidationError(
            reason: "element '\(child.name.localName)' has abstract type '\(bare)' and requires an xsi:type naming a concrete derived type",
            at: path,
        )
    }

    /// The error when an `xsi:type` substitution is forbidden by `block` on the
    /// declared type: the substituted type reaches the declared type by a method
    /// the declared type lists in `block`. Returns nil when there is no named
    /// declared type, no `block`, or the substitution is permitted.
    func blockedSubstitutionError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard case let .typeReference(reference) = declared,
              let substitute = Self.xsiTypeName(child),
              Self.resolveNamedType(substitute, in: types) != nil
        else {
            return nil
        }
        // A ref'd child carries its type as an element-ref key (`element:foo`)
        // that resolves through `types` to the concrete type; follow that chain
        // to the declared type name the derivation backbone and `block` use.
        var declaredKey = reference
        var declaredName = PureXML.Schema.XSDParser.bareTypeLocalName(reference)
        var steps = 0
        while steps <= types.count {
            guard let resolved = types[declaredKey] ?? Self.resolveNamedType(declaredKey, in: types),
                  case let .typeReference(next) = resolved
            else { break }
            declaredKey = next
            declaredName = PureXML.Schema.XSDParser.bareTypeLocalName(next)
            steps += 1
        }
        guard let methods = PureXML.Schema.XSDParser.derivationMethods(from: substitute, to: declaredName, typeDerivation) else {
            return nil
        }
        // The substitution is blocked when the derivation method is disallowed by
        // either the declared type's `block` or the element declaration's own
        // `block` (keyed by the element's name).
        let blocked = (typeBlock[declaredName] ?? []).union(elementBlock[child.name.localName] ?? [])
        guard !methods.isDisjoint(with: blocked) else {
            return nil
        }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(substitute)' is blocked: substitution by this derivation is disallowed",
            at: path,
        )
    }

    /// cvc-elt.4.3.2.1: an `xsi:type` must resolve to a type DERIVED from the
    /// element's declared type. This flags ONLY the case where both the declared
    /// type and the substitute resolve to COMPLEX types recorded in the derivation
    /// backbone and there is no derivation path between them (a different branch of
    /// the hierarchy). It deliberately does NOT touch a simple/list/union substitute,
    /// a substitute or declared type absent from the backbone, or the ur-types: there
    /// the relationship cannot be confirmed from the complex-type backbone alone, so
    /// the rule stays silent (under-reject) rather than risk a false positive.
    ///
    /// Disclosed bound: the derivation backbone (`typeDerivation`) is keyed by bare
    /// local name, shared with `blockedSubstitutionError`. Two imported complex types
    /// with the same local name in different namespaces collide in one slot, so a
    /// cross-namespace substitution could in principle be misjudged. This is a
    /// pre-existing, subsystem-wide limitation (not introduced here); the holistic
    /// fix is to key the backbone by namespaced type identity and resolve `xsi:type`
    /// through `xsiTypeReference`. The XSTS corpus exercises no such collision.
    func notDerivedSubstitutionError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard case let .typeReference(reference) = declared,
              let substitute = Self.xsiTypeName(child),
              case .complex? = Self.resolveNamedType(substitute, in: types)
        else { return nil }
        let substituteName = PureXML.Schema.XSDParser.bareTypeLocalName(substitute)
        let declaredName = resolvedDeclaredTypeName(reference)
        guard substituteName != declaredName,
              typeDerivation[substituteName] != nil,
              typeDerivation[declaredName] != nil || isComplexBackboneRoot(declaredName),
              PureXML.Schema.XSDParser.derivationMethods(from: substituteName, to: declaredName, typeDerivation) == nil
        else { return nil }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(substitute)' is not validly derived from the declared type '\(declaredName)' of '\(child.name.localName)'",
            at: path,
        )
    }

    /// A complex type that heads a derivation backbone (some recorded type derives
    /// from it) even though it records no base of its own, so it is a legitimate
    /// declared-type target for the not-derived check.
    private func isComplexBackboneRoot(_ name: String) -> Bool {
        guard name != "anyType", name != "anySimpleType" else { return false }
        return typeDerivation.values.contains { $0.base == name }
    }

    /// Follows an element-ref / type-reference chain (`element:foo` -> concrete type)
    /// to the declared type's bare local name, which the derivation backbone is
    /// keyed by.
    private func resolvedDeclaredTypeName(_ reference: String) -> String {
        var key = reference
        var name = PureXML.Schema.XSDParser.bareTypeLocalName(reference)
        var steps = 0
        while steps <= types.count {
            guard let resolved = types[key] ?? Self.resolveNamedType(key, in: types),
                  case let .typeReference(next) = resolved
            else { break }
            key = next
            name = PureXML.Schema.XSDParser.bareTypeLocalName(next)
            steps += 1
        }
        return name
    }
}
