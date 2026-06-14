extension PureXML.Schema {
    /// XSD 1.0 "Particle Valid (Restriction)" for the common cases: a complex
    /// type derived by restriction must have a content model that accepts a
    /// subset of its base's. Covers element-vs-element name matching,
    /// element-vs-wildcard admission, wildcard narrowing, occurrence-range
    /// subsumption, and the group recursions (sequence/all order-preserving with
    /// emptiable skips, choice mapping, sequence-into-choice, sequence-into-all).
    /// The spec's effective-total-range arithmetic for MapAndSum is approximated
    /// by per-particle checks, a documented simplification.
    enum ParticleRestriction {
        /// The reason a restriction's content is not a valid subset of its
        /// base's, or nil when it is. `types` resolves an element's
        /// ``ElementType/typeReference`` so element-vs-element pairs can check that
        /// the restricting type derives from the base's (NameAndTypeOK).
        static func violation(restricted: ContentType, base: ContentType, types: [String: ElementType]) -> String? {
            switch (restricted, base) {
            case (.empty, .empty), (.simpleContent, _), (_, .simpleContent):
                nil
            case let (.empty, .elementOnly(baseParticle)), let (.empty, .mixed(baseParticle)):
                emptiable(baseParticle) ? nil : "the base content is required, so the restriction cannot be EMPTY"
            case (.mixed, .elementOnly):
                "a restriction cannot add mixed content to an element-only base"
            case (.elementOnly, .empty), (.mixed, .empty):
                "the base content is EMPTY, so the restriction cannot add content"
            case let (.elementOnly(restrictedParticle), .elementOnly(baseParticle)),
                 let (.elementOnly(restrictedParticle), .mixed(baseParticle)),
                 let (.mixed(restrictedParticle), .mixed(baseParticle)):
                valid(restrictedParticle, baseParticle, types)
                    ? nil
                    : "the restricted content model is not a subset of the base's"
            }
        }

        /// Whether `restricted` accepts a subset of `base` (the pairwise check).
        static func valid(_ restricted: Particle, _ base: Particle, _ types: [String: ElementType]) -> Bool {
            guard rangeSubsumed(restricted, base) else { return false }
            switch (restricted.term, base.term) {
            case let (.element(restrictedName, restrictedType), .element(baseName, baseType)):
                return sameName(restrictedName, baseName) && elementTypeRestrictionOK(restrictedType, baseType, types)
            case let (.element(name, _), .wildcard(wildcard)):
                return wildcard.admits(name)
            case let (.wildcard(restrictedWildcard), .wildcard(baseWildcard)):
                return narrows(restrictedWildcard, baseWildcard)
            case let (.element, .group(baseGroup)):
                // RecurseAsIfGroup: the lone element, as a one-particle sequence,
                // against the base group.
                return groupValid(Group(compositor: .sequence, particles: [restricted.withUnitRange()]), baseGroup, types)
            case let (.group(restrictedGroup), .group(baseGroup)):
                return groupValid(restrictedGroup, baseGroup, types)
            case let (.group(restrictedGroup), .wildcard(wildcard)):
                // NSRecurseCheckCardinality, namespace part: every leaf element
                // the group can contain must be admitted by the wildcard.
                return leafNames(of: restrictedGroup).allSatisfy { wildcard.admits($0) }
            default:
                return false
            }
        }

        private static func groupValid(_ restricted: Group, _ base: Group, _ types: [String: ElementType]) -> Bool {
            switch (restricted.compositor, base.compositor) {
            case (.sequence, .sequence), (.all, .all):
                recurse(restricted.particles, base.particles, skippedMustBeEmptiable: true, types)
            case (.choice, .choice):
                recurse(restricted.particles, base.particles, skippedMustBeEmptiable: false, types)
            case (.sequence, .choice):
                // MapAndSum (simplified): each restricted particle fits some branch.
                restricted.particles.allSatisfy { particle in
                    base.particles.contains { valid(particle, $0, types) }
                }
            case (.sequence, .all):
                // RecurseUnordered: map onto distinct base particles in any order.
                recurseUnordered(restricted.particles, base.particles, types)
            default:
                false
            }
        }

        /// Order-preserving mapping of the restricted particles onto the base's.
        /// A skipped base particle must be emptiable for sequence/all (Recurse);
        /// for choice (RecurseLax) skipping is free.
        private static func recurse(_ restricted: [Particle], _ base: [Particle], skippedMustBeEmptiable: Bool, _ types: [String: ElementType]) -> Bool {
            var baseIndex = 0
            for particle in restricted {
                var matched = false
                while baseIndex < base.count {
                    let candidate = base[baseIndex]
                    baseIndex += 1
                    if valid(particle, candidate, types) {
                        matched = true
                        break
                    }
                    if skippedMustBeEmptiable, !emptiable(candidate) { return false }
                }
                if !matched { return false }
            }
            if skippedMustBeEmptiable {
                while baseIndex < base.count {
                    if !emptiable(base[baseIndex]) { return false }
                    baseIndex += 1
                }
            }
            return true
        }

        /// Any-order mapping onto distinct base particles; unmapped base
        /// particles must be emptiable.
        private static func recurseUnordered(_ restricted: [Particle], _ base: [Particle], _ types: [String: ElementType]) -> Bool {
            var used = [Bool](repeating: false, count: base.count)
            for particle in restricted {
                guard let index = base.indices.first(where: { !used[$0] && valid(particle, base[$0], types) }) else {
                    return false
                }
                used[index] = true
            }
            return base.indices.allSatisfy { used[$0] || emptiable(base[$0]) }
        }

        /// A conservative slice of NameAndTypeOK. Two checks, both over-rejection-safe:
        /// restricting an element to an ur-type (`anyType`/`anySimpleType`) when the
        /// base has a concrete type is always widening, hence invalid; and when both
        /// elements resolve to atomic simple types, the restricting type's built-in
        /// base must derive from the base's (so an `xs:string` element renamed to
        /// `xs:int` is rejected). Any other pairing (complex content, a list/union
        /// variety, a named user type whose derivation the flattened particle model
        /// does not record) is permitted, so no valid restriction is rejected.
        private static func elementTypeRestrictionOK(_ restricted: ElementType?, _ base: ElementType?, _ types: [String: ElementType]) -> Bool {
            if isUrTypeReference(restricted, types), isConcreteType(base) { return false }
            guard let restrictedSimple = resolvedAtomic(restricted, types),
                  let baseSimple = resolvedAtomic(base, types)
            else { return true }
            return restrictedSimple.base.derives(from: baseSimple.base)
        }

        private static let urTypeNames: Set<String> = ["anyType", "anySimpleType", "anyAtomicType"]

        /// Whether an element type is a reference to one of the XSD ur-types (the
        /// widest types, which nothing may be restricted *to* from a narrower base).
        /// A genuine ur-type is not in the named-type table; a user type that merely
        /// shares the local name (in another namespace) is, so checking absence keeps
        /// the namespace-blind reference key from misclassifying it.
        private static func isUrTypeReference(_ type: ElementType?, _ types: [String: ElementType]) -> Bool {
            if case let .typeReference(key) = type { return urTypeNames.contains(key) && types[key] == nil }
            return false
        }

        /// Whether an element type names a concrete type (a built-in or a non-ur user
        /// type), as opposed to an ur-type or an absent/unknown type.
        private static func isConcreteType(_ type: ElementType?) -> Bool {
            switch type {
            case .simple: true
            case let .typeReference(key): !urTypeNames.contains(key)
            case .complex, .none: false
            }
        }

        /// The atomic ``SimpleType`` an element type resolves to (following
        /// ``ElementType/typeReference`` through `types`), or nil for a complex,
        /// list/union, or unresolvable type.
        private static func resolvedAtomic(_ type: ElementType?, _ types: [String: ElementType]) -> SimpleType? {
            var current = type
            var steps = 0
            while let resolved = current, steps <= types.count {
                switch resolved {
                case let .simple(simple):
                    guard case .atomic = simple.variety else { return nil }
                    return simple
                case .complex:
                    return nil
                case let .typeReference(key):
                    current = types[key]
                    steps += 1
                }
            }
            return nil
        }

        /// Occurrence-range subsumption: the restriction may not occur less often
        /// than the base requires, nor more often than the base allows.
        private static func rangeSubsumed(_ restricted: Particle, _ base: Particle) -> Bool {
            guard restricted.minOccurs >= base.minOccurs else { return false }
            guard let baseMax = base.maxOccurs else { return true }
            guard let restrictedMax = restricted.maxOccurs else { return false }
            return restrictedMax <= baseMax
        }

        /// Whether a particle can match no children at all.
        static func emptiable(_ particle: Particle) -> Bool {
            if particle.minOccurs == 0 { return true }
            switch particle.term {
            case .element, .wildcard:
                return false
            case let .group(group):
                switch group.compositor {
                case .sequence, .all:
                    return group.particles.allSatisfy(emptiable)
                case .choice:
                    return group.particles.contains(where: emptiable)
                }
            }
        }

        /// Whether the restricted wildcard admits no namespace the base refuses.
        private static func narrows(_ restricted: Wildcard, _ base: Wildcard) -> Bool {
            switch (restricted.namespace, base.namespace) {
            case (_, .any):
                true
            case (.other, .other):
                restricted.targetNamespace == base.targetNamespace
            case let (.enumerated(narrow), .enumerated(wide)):
                narrow.isSubset(of: wide)
            case let (.enumerated(narrow), .other):
                !narrow.contains("") && !narrow.contains(base.targetNamespace ?? "")
            default:
                false
            }
        }

        private static func sameName(_ lhs: PureXML.Model.QualifiedName, _ rhs: PureXML.Model.QualifiedName) -> Bool {
            lhs.localName == rhs.localName && (lhs.namespaceURI ?? "") == (rhs.namespaceURI ?? "")
        }

        /// Every element name a group can contain (its alphabet).
        private static func leafNames(of group: Group) -> [PureXML.Model.QualifiedName] {
            group.particles.flatMap { particle -> [PureXML.Model.QualifiedName] in
                switch particle.term {
                case let .element(name, _): [name]
                case let .group(inner): leafNames(of: inner)
                case .wildcard: []
                }
            }
        }
    }
}

private extension PureXML.Schema.Particle {
    /// A copy occurring exactly once, for RecurseAsIfGroup's wrapping.
    func withUnitRange() -> PureXML.Schema.Particle {
        .init(minOccurs: minOccurs, maxOccurs: maxOccurs, term: term)
    }
}
