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
        static func violation(restricted: ContentType, base: ContentType, types: [String: ElementType], derivation: [String: TypeDerivation]) -> String? {
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
                valid(restrictedParticle, baseParticle, types, derivation)
                    ? nil
                    : "the restricted content model is not a subset of the base's"
            }
        }

        /// Whether `restricted` accepts a subset of `base` (the pairwise check).
        static func valid(_ restricted: Particle, _ base: Particle, _ types: [String: ElementType], _ derivation: [String: TypeDerivation]) -> Bool {
            guard rangeSubsumed(restricted, base) else { return false }
            switch (restricted.term, base.term) {
            case let (.element(restrictedName, _, restrictedTypeName), .element(baseName, _, baseTypeName)):
                return sameName(restrictedName, baseName) && elementTypeRestrictionOK(restrictedTypeName, baseTypeName, types, derivation)
            case let (.element(name, _, _), .wildcard(wildcard)):
                return wildcard.admits(name)
            case let (.wildcard(restrictedWildcard), .wildcard(baseWildcard)):
                return narrows(restrictedWildcard, baseWildcard)
            case let (.element, .group(baseGroup)):
                // RecurseAsIfGroup: the lone element, as a one-particle sequence,
                // against the base group.
                return groupValid(Group(compositor: .sequence, particles: [restricted.withUnitRange()]), baseGroup, types, derivation)
            case let (.group(restrictedGroup), .group(baseGroup)):
                return groupValid(restrictedGroup, baseGroup, types, derivation)
            case let (.group(restrictedGroup), .wildcard(wildcard)):
                // NSRecurseCheckCardinality, namespace part: every leaf element
                // the group can contain must be admitted by the wildcard.
                return leafNames(of: restrictedGroup).allSatisfy { wildcard.admits($0) }
            default:
                return false
            }
        }

        private static func groupValid(_ restricted: Group, _ base: Group, _ types: [String: ElementType], _ derivation: [String: TypeDerivation]) -> Bool {
            switch (restricted.compositor, base.compositor) {
            case (.sequence, .sequence), (.all, .all):
                recurse(restricted.particles, base.particles, skippedMustBeEmptiable: true, types, derivation)
            case (.choice, .choice):
                recurse(restricted.particles, base.particles, skippedMustBeEmptiable: false, types, derivation)
            case (.sequence, .choice):
                // MapAndSum (simplified): each restricted particle fits some branch.
                restricted.particles.allSatisfy { particle in
                    base.particles.contains { valid(particle, $0, types, derivation) }
                }
            case (.sequence, .all):
                // RecurseUnordered: map onto distinct base particles in any order.
                recurseUnordered(restricted.particles, base.particles, types, derivation)
            default:
                false
            }
        }

        /// Order-preserving mapping of the restricted particles onto the base's.
        /// A skipped base particle must be emptiable for sequence/all (Recurse);
        /// for choice (RecurseLax) skipping is free.
        private static func recurse(
            _ restricted: [Particle],
            _ base: [Particle],
            skippedMustBeEmptiable: Bool,
            _ types: [String: ElementType],
            _ derivation: [String: TypeDerivation],
        ) -> Bool {
            var baseIndex = 0
            for particle in restricted {
                var matched = false
                while baseIndex < base.count {
                    let candidate = base[baseIndex]
                    baseIndex += 1
                    if valid(particle, candidate, types, derivation) {
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
        private static func recurseUnordered(_ restricted: [Particle], _ base: [Particle], _ types: [String: ElementType], _ derivation: [String: TypeDerivation]) -> Bool {
            var used = [Bool](repeating: false, count: base.count)
            for particle in restricted {
                guard let index = base.indices.first(where: { !used[$0] && valid(particle, base[$0], types, derivation) }) else {
                    return false
                }
                used[index] = true
            }
            return base.indices.allSatisfy { used[$0] || emptiable(base[$0]) }
        }

        /// NameAndTypeOK type clause: the restricting element's type must be, or
        /// derive by restriction from, the base element's type. Element types carry
        /// their derivation identity as a `typeName` (a built-in, a user type, or
        /// `anyType` for an absent type; nil for an inline anonymous type). When both
        /// names are known the answer is decided by name; an inline anonymous type on
        /// either side is permitted (its derivation identity is not recorded), which
        /// can only under-reject, so no valid restriction is rejected.
        private static func elementTypeRestrictionOK(
            _ restrictedTypeName: String?,
            _ baseTypeName: String?,
            _ types: [String: ElementType],
            _ derivation: [String: TypeDerivation],
        ) -> Bool {
            guard let restrictedTypeName, let baseTypeName else { return true }
            // A type validly derives from a union by being one of its members, which
            // is not a restriction chain over type names, so when the base resolves to
            // a union variety the name check stands down (permit) rather than misread
            // the membership as unrelated. (A list base stays checked: a valid
            // list-typed restriction is the same named list or a restriction of it,
            // which the derivation chain does capture.)
            if baseIsUnion(baseTypeName, types) { return true }
            return typeDerivesOrEqual(restrictedTypeName, baseTypeName, derivation, types)
        }

        /// Whether the named type resolves (through the type table) to a `union`
        /// simple type.
        private static func baseIsUnion(_ name: String, _ types: [String: ElementType]) -> Bool {
            var current: ElementType? = types[name]
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

        private static let urTypeNames: Set<String> = ["anyType", "anySimpleType", "anyAtomicType"]

        private static func isUrTypeName(_ name: String, _ types: [String: ElementType]) -> Bool {
            urTypeNames.contains(name) && types[name] == nil
        }

        /// Whether the type named `derived` is, or is validly derived by restriction
        /// from, the type named `base`: any type derives from an ur-type base; a name
        /// equal to the base matches; the user-declared restriction chain is walked
        /// (`derivation`), and where it bottoms out in a built-in the lattice
        /// continues it. Names are compared as the compiler resolves them (by local
        /// name), so an unrelated pair (`xs:string` restricting a user type, two
        /// independent list types) is correctly not derivable.
        private static func typeDerivesOrEqual(_ derived: String, _ base: String, _ derivation: [String: TypeDerivation], _ types: [String: ElementType]) -> Bool {
            if isUrTypeName(base, types) { return true }
            var current = derived
            var visited: Set<String> = []
            while visited.insert(current).inserted {
                if current == base { return true }
                guard let step = derivation[current] else { break }
                current = step.base
            }
            if let derivedBuiltin = BuiltinType(rawValue: current), let baseBuiltin = BuiltinType(rawValue: base) {
                return derivedBuiltin.derives(from: baseBuiltin)
            }
            return current == base
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
                case let .element(name, _, _): [name]
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
