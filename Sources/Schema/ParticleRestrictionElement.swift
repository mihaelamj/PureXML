extension PureXML.Schema.ParticleRestriction {
    /// NameAndTypeOK type clause: the restricting element's type must be, or
    /// derive by restriction from, the base element's type. Element types carry
    /// their derivation identity as a `typeName` (a built-in, a user type, or
    /// `anyType` for an absent type; nil for an inline anonymous type). When both
    /// names are known the answer is decided by name; an inline anonymous type on
    /// either side is permitted (its derivation identity is not recorded), which
    /// can only under-reject, so no valid restriction is rejected.
    private static func resolveType(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> PureXML.Schema.ElementType? {
        let local = PureXML.Schema.XSDNode.stripPrefix(name)
        if let builtin = PureXML.Schema.BuiltinType(rawValue: local) {
            return .simple(PureXML.Schema.SimpleType(base: builtin))
        }
        if local == "anySimpleType" {
            return .simple(PureXML.Schema.SimpleType(base: .string, isAnySimpleType: true))
        }
        if local == "anyType" {
            return .complex(PureXML.Schema.ComplexType())
        }
        var current: PureXML.Schema.ElementType? = types[local]
        var steps = 0
        while let resolved = current, steps <= types.count {
            if case let .typeReference(key) = resolved {
                current = types[key]
                steps += 1
            } else {
                return resolved
            }
        }
        return nil
    }

    static func elementTypeRestrictionOK(
        _ restrictedTypeName: String?,
        _ baseTypeName: String?,
        _ types: [String: PureXML.Schema.ElementType],
        _ derivation: [String: PureXML.Schema.TypeDerivation],
    ) -> Bool {
        guard let restrictedTypeName, let baseTypeName else { return true }

        if let baseResolved = resolveType(baseTypeName, types), let derivedResolved = resolveType(restrictedTypeName, types) {
            switch (derivedResolved, baseResolved) {
            case let (.simple(derivedSimple), .simple(baseSimple)):
                if case .union = baseSimple.variety {
                    return PureXML.Schema.XSDParser.isSimpleTypeRestrictionOK(derived: derivedSimple, base: baseSimple)
                }
            case (.complex, .simple):
                return false
            case (.simple, .complex):
                return PureXML.Schema.XSDNode.stripPrefix(baseTypeName) == "anyType"
            default:
                break
            }
        }

        if baseIsUnion(baseTypeName, types) { return true }
        // NameAndTypeOK.2.2: a restricting element's type must be validly derived from
        // the base element's type EXCLUDING extension (and list/union), i.e. by
        // restriction only. A type that reaches the base through an extension step is
        // not a valid restriction. (Union-base cases are still handled above; the
        // by-name restriction-derivation of a union member is a separate clause.)
        return typeDerivesByRestriction(restrictedTypeName, baseTypeName, derivation, types)
    }

    /// Whether the named type resolves (through the type table) to a `union`
    /// simple type.
    private static func baseIsUnion(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool {
        var current: PureXML.Schema.ElementType? = types[name]
        var steps = 0
        while let resolved = current, steps <= types.count {
            switch resolved {
            case let .simple(simple):
                if case .union = simple.variety { return true }
                return false
            case .complex:
                return false
            case let .typeReference(key):
                current = types[key]
                steps += 1
            }
        }
        return false
    }

    private static var urTypeNames: Set<String> {
        ["anyType", "anySimpleType", "anyAtomicType"]
    }

    private static func isUrTypeName(_ name: String, _ types: [String: PureXML.Schema.ElementType]) -> Bool {
        urTypeNames.contains(name) && types[name] == nil
    }

    /// Whether the type named `derived` is, or is validly derived by restriction
    /// from, the type named `base`: any type derives from an ur-type base; a name
    /// equal to the base matches; the user-declared restriction chain is walked
    /// (`derivation`), and where it bottoms out in a built-in the lattice
    /// continues it. Names are compared as the compiler resolves them (by local
    /// name), so an unrelated pair (`xs:string` restricting a user type, two
    /// independent list types) is correctly not derivable.
    static func typeDerivesOrEqual(
        _ derived: String,
        _ base: String,
        _ derivation: [String: PureXML.Schema.TypeDerivation],
        _ types: [String: PureXML.Schema.ElementType],
    ) -> Bool {
        if isUrTypeName(base, types) { return true }
        var current = derived
        var visited: Set<String> = []
        while visited.insert(current).inserted {
            if current == base { return true }
            guard let step = derivation[current] else { break }
            current = step.base
        }
        if let derivedBuiltin = PureXML.Schema.BuiltinType(rawValue: current), let baseBuiltin = PureXML.Schema.BuiltinType(rawValue: base) {
            return derivedBuiltin.derives(from: baseBuiltin)
        }
        return current == base
    }

    /// As ``typeDerivesOrEqual``, but the user-declared chain is followed ONLY across
    /// `restriction` steps (an `extension` step breaks the walk), so a type derived by
    /// extension does not count as a restriction of its base. Built-in derivation is
    /// always by restriction, so the lattice continuation is unchanged. A `restriction`
    /// of a union (declared `<restriction base="thatUnion">`) is reached through the
    /// chain; an unrelated union with subset members is not. The ur-type base stays
    /// permissive (any type restricts the ur-type), matching ``typeDerivesOrEqual``.
    static func typeDerivesByRestriction(
        _ derived: String,
        _ base: String,
        _ derivation: [String: PureXML.Schema.TypeDerivation],
        _ types: [String: PureXML.Schema.ElementType],
    ) -> Bool {
        if isUrTypeName(base, types) { return true }
        var current = derived
        var visited: Set<String> = []
        while visited.insert(current).inserted {
            if current == base { return true }
            guard let step = derivation[current], step.method == .restriction else { break }
            current = step.base
        }
        if let derivedBuiltin = PureXML.Schema.BuiltinType(rawValue: current), let baseBuiltin = PureXML.Schema.BuiltinType(rawValue: base) {
            return derivedBuiltin.derives(from: baseBuiltin)
        }
        return current == base
    }
}
