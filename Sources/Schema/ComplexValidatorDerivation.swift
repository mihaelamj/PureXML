extension PureXML.Schema.ComplexValidator {
    /// The error when an element's declared type is an abstract complex type and
    /// the element supplies no `xsi:type` to name a concrete derived type. An
    /// abstract type cannot itself be the type of an instance element.
    func abstractTypeError(
        named name: String,
        child: PureXML.Model.Element,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard abstractTypes.contains(name), Self.xsiTypeName(child) == nil else { return nil }
        return PureXML.Validation.ValidationError(
            reason: "element '\(child.name.localName)' has abstract type '\(name)' and requires an xsi:type naming a concrete derived type",
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
        guard case let .typeReference(declaredName) = declared,
              let substitute = Self.xsiTypeName(child), types[substitute] != nil,
              let blocked = typeBlock[declaredName],
              let methods = PureXML.Schema.XSDParser.derivationMethods(from: substitute, to: declaredName, typeDerivation),
              !methods.isDisjoint(with: blocked)
        else {
            return nil
        }
        return PureXML.Validation.ValidationError(
            reason: "xsi:type '\(substitute)' is blocked: type '\(declaredName)' disallows substitution by this derivation",
            at: path,
        )
    }
}
