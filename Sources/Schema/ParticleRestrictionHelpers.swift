extension PureXML.Schema.ParticleRestriction {
    /// Every element-declaration term reachable as a leaf of `group` (recursing
    /// into nested groups; wildcards are not elements). Used to test whether a
    /// restricting element names something the base group admits.
    static func elementLeaves(of group: PureXML.Schema.Group) -> [PureXML.Schema.Term] {
        group.particles.flatMap { particle -> [PureXML.Schema.Term] in
            switch particle.term {
            case .element: [particle.term]
            case let .group(inner): elementLeaves(of: inner)
            case .wildcard: []
            }
        }
    }

    /// Validation strength of a wildcard's `processContents`, for the Wildcard
    /// Subset rule: `strict` is stronger than `lax` is stronger than `skip`.
    static func processContentsRank(_ processContents: PureXML.Schema.ProcessContents) -> Int {
        switch processContents {
        case .skip: 0
        case .lax: 1
        case .strict: 2
        }
    }

    /// NameAndTypeOK value-constraint clause: when the base element is `fixed`, the
    /// restricting element must also be `fixed` to the same value (compared in the
    /// base type's value space, so `1` and `01` match). A base with no fixed value,
    /// or a `default`, imposes no constraint on the restriction.
    static func fixedValueOK(
        _ restrictedValue: PureXML.Schema.ValueConstraint?,
        _ baseValue: PureXML.Schema.ValueConstraint?,
        _ baseType: PureXML.Schema.ElementType?,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> Bool {
        guard let baseFixed = baseValue?.fixedValue else { return true }
        guard let restrictedFixed = restrictedValue?.fixedValue else { return false }
        return atomicType(baseType, types)?.valueMatches(restrictedFixed, literal: baseFixed) ?? (restrictedFixed == baseFixed)
    }

    /// The atomic simple type an element's type resolves to (following a
    /// `typeReference` through the types map, bounded against cycles), or nil for a
    /// complex, list, or union type.
    static func atomicType(_ type: PureXML.Schema.ElementType?, _ types: [String: PureXML.Schema.ElementType], _ depth: Int = 0) -> PureXML.Schema.SimpleType? {
        guard depth < 32 else { return nil }
        switch type {
        case let .simple(simple): return simple
        case let .typeReference(key): return atomicType(types[key], types, depth + 1)
        default: return nil
        }
    }
}
