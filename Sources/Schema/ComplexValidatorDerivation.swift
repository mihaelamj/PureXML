extension PureXML.Schema.ComplexValidator {
    /// The first `xsi:type` override error for `child`, if any: a substitution
    /// blocked by `block`, a substitute not validly derived from the declared type
    /// (cvc-elt.4.3.2.1), or a missing `xsi:type` on an abstract declared type.
    ///
    /// The derivation backbone (`typeDerivation`), `block` tables, and abstract-type
    /// set are keyed by namespaced identity (`{ns}local`), so two imported types
    /// sharing a local name in different namespaces do not collide. The declared
    /// type's reference (`type:{ns}local`) and the instance `xsi:type` (resolved
    /// through the element's prefix bindings) are both reduced to that key.
    func xsiTypeOverrideError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
        namespaceBindings: [String: String],
    ) -> PureXML.Validation.ValidationError? {
        if let blocked = blockedSubstitutionError(declared: declared, child: child, at: path, namespaceBindings: namespaceBindings) { return blocked }
        if let notDerived = notDerivedSubstitutionError(declared: declared, child: child, at: path, namespaceBindings: namespaceBindings) { return notDerived }
        if let listUnion = listUnionSubstitutionError(declared: declared, child: child, at: path, namespaceBindings: namespaceBindings) { return listUnion }
        if let abstractType = abstractXsiTypeError(child: child, at: path, namespaceBindings: namespaceBindings) { return abstractType }
        if case let .typeReference(name) = declared { return abstractTypeError(named: name, child: child, at: path) }
        return nil
    }

    /// The error when an instance `xsi:type` names an ABSTRACT type: an abstract
    /// type cannot be the type of an instance element (cvc-elt.4.3.2), so it may not
    /// be used as a substitution. Distinct from ``abstractTypeError``, which covers
    /// an abstract DECLARED type with no `xsi:type`.
    func abstractXsiTypeError(
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
        namespaceBindings: [String: String],
    ) -> PureXML.Validation.ValidationError? {
        guard let label = Self.xsiTypeName(child),
              let reference = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings),
              abstractTypes.contains(Self.derivationKey(fromReference: reference))
        else { return nil }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(label)' names an abstract type and may not be used as a substitution",
            at: path,
        )
    }

    /// cvc-elt.4.3.2.1 for a list or union `xsi:type`: a list or union simple type
    /// is derived only from `anySimpleType`, so it can validly stand in only for an
    /// element whose declared type is a ur-type (`anySimpleType`/`anyType`). Naming a
    /// list or union type on an element of any more specific atomic or complex type
    /// is not a valid derivation. When the declared type is itself a list or union
    /// the check stays silent (an inline list/union identity cannot be matched), so
    /// it biases to under-reject and never over-rejects.
    func listUnionSubstitutionError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
        namespaceBindings: [String: String],
    ) -> PureXML.Validation.ValidationError? {
        guard let label = Self.xsiTypeName(child),
              let reference = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings),
              case let .simple(substitute)? = Self.resolveNamedType(reference, in: types),
              Self.isListOrUnion(substitute),
              !declaredAdmitsAnySimpleType(declared)
        else { return nil }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(label)' is a list or union type not validly derived from the declared type of '\(child.name.localName)'",
            at: path,
        )
    }

    /// Whether a list or union substitute may validly stand in for `declared`: only
    /// the ur-types (`anySimpleType`/`anyType`) admit one. A declared type that is
    /// itself a list or union, or an unresolvable reference, is also treated as
    /// admitting, so the list/union check stays silent rather than risk a false
    /// positive on an inline or unknown declared type.
    private func declaredAdmitsAnySimpleType(_ declared: PureXML.Schema.ElementType) -> Bool {
        let resolved: PureXML.Schema.ElementType? = switch declared {
        case .simple, .complex: declared
        case let .typeReference(reference): resolvedDeclaredType(reference)
        }
        switch resolved {
        case let .simple(type): return type.isAnySimpleType || Self.isListOrUnion(type)
        case let .complex(type): return Self.isUrType(type)
        default: return true
        }
    }

    /// Follows an element-ref / type-reference chain (`element:foo` -> concrete type)
    /// to the concrete declared type (a `.simple` or `.complex`), or nil when the
    /// chain does not resolve. The name-returning ``resolvedDeclaredTypeName`` walks
    /// the same chain for the backbone key.
    private func resolvedDeclaredType(_ reference: String) -> PureXML.Schema.ElementType? {
        var key = reference
        var resolved = types[key] ?? Self.resolveNamedType(key, in: types)
        var steps = 0
        while case let .typeReference(next)? = resolved, steps <= types.count {
            key = next
            resolved = types[key] ?? Self.resolveNamedType(key, in: types)
            steps += 1
        }
        return resolved
    }

    /// Whether a simple type is a list or union (deriving only from `anySimpleType`).
    static func isListOrUnion(_ type: PureXML.Schema.SimpleType) -> Bool {
        switch type.variety {
        case .atomic: false
        case .list, .union: true
        }
    }

    /// Whether a substitute type participates in the not-derived check: a complex
    /// type, or an ATOMIC simple type. A list or union substitute is excluded here
    /// (it is handled by ``listUnionSubstitutionError``).
    static func isAtomicOrComplex(_ type: PureXML.Schema.ElementType) -> Bool {
        switch type {
        case .complex: true
        case let .simple(simple): !isListOrUnion(simple)
        case .typeReference: false
        }
    }

    /// Whether an element type resolves to a complex type.
    static func isComplexType(_ type: PureXML.Schema.ElementType) -> Bool {
        if case .complex = type { return true }
        return false
    }

    /// The error when an element's declared type is an abstract complex type and
    /// the element supplies no `xsi:type` to name a concrete derived type. An
    /// abstract type cannot itself be the type of an instance element.
    func abstractTypeError(
        named name: String,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard abstractTypes.contains(resolvedDeclaredTypeName(name)),
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
        namespaceBindings: [String: String],
    ) -> PureXML.Validation.ValidationError? {
        guard case let .typeReference(reference) = declared,
              let substituteLabel = Self.xsiTypeName(child),
              let substituteRef = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings),
              Self.resolveNamedType(substituteRef, in: types) != nil
        else {
            return nil
        }
        let substituteKey = Self.derivationKey(fromReference: substituteRef)
        let declaredName = resolvedDeclaredTypeName(reference)
        guard let methods = PureXML.Schema.XSDParser.derivationMethods(from: substituteKey, to: declaredName, typeDerivation) else {
            return nil
        }
        // The substitution is blocked when the derivation method is disallowed by
        // either the declared type's `block` or the element declaration's own
        // `block`, both keyed by namespaced identity.
        let blocked = (typeBlock[declaredName] ?? []).union(elementBlock[Self.key(child.name)] ?? [])
        guard !methods.isDisjoint(with: blocked) else {
            return nil
        }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(substituteLabel)' is blocked: substitution by this derivation is disallowed",
            at: path,
        )
    }

    /// cvc-elt.4.3.2.1: an `xsi:type` must resolve to a type DERIVED from the
    /// element's declared type. This flags the case where both the declared type and
    /// the substitute resolve to complex or atomic-simple types recorded in the
    /// derivation backbone and there is no derivation path between them (a different
    /// branch of the hierarchy, including a substitute that is the declared type's
    /// own ancestor). A list or union substitute is handled separately by
    /// ``listUnionSubstitutionError``; a substitute or declared type ABSENT from the
    /// backbone (a built-in, or the ur-types) leaves the relationship unconfirmable,
    /// so the rule stays silent (under-reject) rather than risk a false positive.
    func notDerivedSubstitutionError(
        declared: PureXML.Schema.ElementType,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
        namespaceBindings: [String: String],
    ) -> PureXML.Validation.ValidationError? {
        guard case let .typeReference(reference) = declared,
              let substituteLabel = Self.xsiTypeName(child),
              let substituteRef = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings),
              let substituteType = Self.resolveNamedType(substituteRef, in: types),
              Self.isAtomicOrComplex(substituteType)
        else { return nil }
        let substituteKey = Self.derivationKey(fromReference: substituteRef)
        let declaredName = resolvedDeclaredTypeName(reference)
        // A complex substitute is in scope even when it records no base of its own:
        // a baseless complex type derives only from `anyType`, so it cannot derive
        // from the declared (non-ur) type and is correctly flagged. An atomic
        // substitute must be in the backbone, so a built-in (which derives by the
        // primitive hierarchy the backbone does not record) stays silent.
        let substituteInScope = Self.isComplexType(substituteType) || typeDerivation[substituteKey] != nil
        guard substituteKey != declaredName,
              substituteInScope,
              typeDerivation[declaredName] != nil || isComplexBackboneRoot(declaredName),
              PureXML.Schema.XSDParser.derivationMethods(from: substituteKey, to: declaredName, typeDerivation) == nil
        else { return nil }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(substituteLabel)' is not validly derived from the declared type of '\(child.name.localName)'",
            at: path,
        )
    }

    /// A complex type that heads a derivation backbone (some recorded type derives
    /// from it) even though it records no base of its own, so it is a legitimate
    /// declared-type target for the not-derived check.
    private func isComplexBackboneRoot(_ name: String) -> Bool {
        let local = PureXML.Schema.XSDParser.unpackElementName(name).0
        guard local != "anyType", local != "anySimpleType" else { return false }
        return typeDerivation.values.contains { $0.base == name }
    }

    /// Follows an element-ref / type-reference chain (`element:foo` -> concrete type)
    /// to the declared type's namespaced derivation key (`{ns}local`), which the
    /// derivation backbone is keyed by.
    private func resolvedDeclaredTypeName(_ reference: String) -> String {
        var key = reference
        var name = Self.derivationKey(fromReference: reference)
        var steps = 0
        while steps <= types.count {
            guard let resolved = types[key] ?? Self.resolveNamedType(key, in: types),
                  case let .typeReference(next) = resolved
            else { break }
            key = next
            name = Self.derivationKey(fromReference: next)
            steps += 1
        }
        return name
    }

    /// The namespaced derivation key (`{ns}local`) a type-table reference reduces
    /// to. A `type:{ns}local` key has its `type:` prefix stripped to leave the
    /// `{ns}local` identity. A bare reference (an unprefixed `xsi:type` resolved in
    /// no namespace, or a built-in name) is normalized to `{}local`, matching the
    /// no-namespace key the backbone records for an unqualified component. An
    /// `element:`/other-keyed reference is left as-is, where it will not match the
    /// namespaced backbone and the check stays silent rather than risk a false
    /// positive.
    static func derivationKey(fromReference reference: String) -> String {
        if reference.hasPrefix("type:") { return String(reference.dropFirst("type:".count)) }
        if reference.hasPrefix("{") || reference.contains(":") { return reference }
        return key(PureXML.Model.QualifiedName(localName: reference, namespaceURI: nil))
    }
}
