extension PureXML.Schema.ComplexValidator {
    /// The declared type after an `xsi:type` override. An override naming an
    /// undeclared type appends an error and returns nil, not a silent fallback
    /// to the declared type.
    func overriddenType(
        _ declared: PureXML.Schema.ElementType,
        for child: PureXML.Model.Element,
        at path: XSDPath,
        into errors: inout [XSDFailure],
    ) -> PureXML.Schema.ElementType? {
        guard let overriding = Self.xsiTypeName(child) else { return declared }
        if let resolved = types[overriding] { return resolved }
        // An xsi:type may name a built-in datatype (xsd:int, xsd:boolean) rather
        // than a schema-declared one. The substitution is valid only when the
        // built-in is validly derived from the declared type (Schema-Validity
        // Assessment, xsi:type): the ur-type admits any type, and a built-in
        // declared type admits the built-ins derived from it. An invalid
        // built-in substitution is a genuine error, not a silent acceptance.
        if let builtin = PureXML.Schema.BuiltinType(rawValue: overriding) {
            if xsiBuiltinSubstitutes(builtin, for: declared) {
                return .simple(PureXML.Schema.SimpleType(base: builtin))
            }
            errors.append(XSDFailure(reason: "xsi:type '\(overriding)' is not validly derived from the declared type of '\(child.name.localName)'", at: path))
            return nil
        }
        errors.append(XSDFailure(reason: "unknown xsi:type '\(overriding)' on '\(child.name.localName)'", at: path))
        return nil
    }

    /// Whether the built-in named by `xsi:type` validly substitutes for the
    /// declared type: the ur-type (`anyType`/`anySimpleType`) admits any type,
    /// and a bare built-in declared type admits any built-in derived from it.
    /// A faceted restriction, a list/union, or any other complex type is never
    /// a valid target for a bare built-in substitution.
    private func xsiBuiltinSubstitutes(_ xsi: PureXML.Schema.BuiltinType, for declared: PureXML.Schema.ElementType) -> Bool {
        switch declared {
        case let .typeReference(name):
            if name == "anyType" || name == "anySimpleType" { return true }
            switch resolveReference(declared) {
            case let .resolved(resolved): return xsiBuiltinSubstitutes(xsi, for: resolved)
            case .unknown, .circular: return false
            }
        case let .simple(simple):
            guard case .atomic = simple.variety, simple.facets.isUnconstrained else { return false }
            return xsi.derives(from: simple.base)
        case let .complex(complex):
            return Self.isUrType(complex)
        }
    }
}
