extension PureXML.Schema.ComplexValidator {
    /// The declared type after an `xsi:type` override. An override naming an
    /// undeclared type appends an error and returns nil, not a silent fallback
    /// to the declared type.
    func overriddenType(
        _ declared: PureXML.Schema.ElementType,
        for child: PureXML.Model.Element,
        namespaceBindings: [String: String] = [:],
        at path: XSDPath,
        into errors: inout [XSDFailure],
    ) -> PureXML.Schema.ElementType? {
        guard Self.xsiTypeAttributeValue(child) != nil else { return declared }
        let reference = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings) ?? Self.xsiTypeName(child) ?? ""
        if let resolved = Self.resolveNamedType(reference, in: types) { return resolved }
        let overriding = Self.xsiTypeName(child) ?? reference
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
            if name == "anyType" || name == "anySimpleType" || name.hasSuffix("}anyType") || name.hasSuffix("}anySimpleType") { return true }
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
