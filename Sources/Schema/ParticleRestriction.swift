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
            case let (.elementOnly(restrictedParticle), .empty):
                // A content-free particle (an empty group, or one whose members all
                // have maxOccurs=0) accepts only the empty sequence, so it is a valid
                // restriction of EMPTY; only a particle that can contribute a child is
                // adding content.
                contentFree(restrictedParticle) ? nil : "the base content is EMPTY, so the restriction cannot add content"
            case (.mixed, .empty):
                "the base content is EMPTY, so the restriction cannot add content"
            case let (.elementOnly(restrictedParticle), .elementOnly(baseParticle)),
                 let (.elementOnly(restrictedParticle), .mixed(baseParticle)),
                 let (.mixed(restrictedParticle), .mixed(baseParticle)):
                // The W3C restriction algorithm is defined over the normalized content
                // model (pointless particles eliminated): a `maxOccurs=0` member
                // removed, a `{1,1}` single-member group unwrapped, a nested
                // same-compositor `{1,1}` group spliced. Without this, e.g. a base
                // `sequence(any{2,3})` is not seen as the wildcard it equals.
                valid(restrictedParticle.normalized(), baseParticle.normalized(), types, derivation)
                    ? nil
                    : "the restricted content model is not a subset of the base's"
            }
        }

        /// Whether `restricted` accepts a subset of `base` (the pairwise check).
        ///
        /// Occurrence subsumption (`rangeSubsumed`) is applied only to the
        /// same-kind pairings (element/element, wildcard/wildcard, group/group) and
        /// element/wildcard, where the two particles' own occurrence ranges are
        /// directly comparable. For the cross-kind pairings (element/group and
        /// group/element via RecurseAsIfGroup; group/wildcard via
        /// NSRecurseCheckCardinality) the occurrence is matched *inside* the case,
        /// against a member or as an effective total range, never the derived
        /// particle's own occurrence against the base group/wildcard's. Applying the
        /// outer check there over-rejects: e.g. `sequence(e1{2,3})` restricting
        /// `sequence(e1{1,3},...)` once the pointless single-member group is
        /// normalized to the bare `e1{2,3}` (`3 > 1` against the base sequence).
        static func valid(_ restricted: Particle, _ base: Particle, _ types: [String: ElementType], _ derivation: [String: TypeDerivation]) -> Bool {
            // A restriction that can never contribute a child (its own `maxOccurs=0`,
            // or a group whose every member is content-free) accepts only the empty
            // sequence, so it is a valid restriction of any emptiable base. Checked
            // before the structural cases, which would otherwise recurse into members
            // that never occur and wrongly reject (e.g. a `maxOccurs="0"` sequence
            // whose members have their own non-trivial occurrences).
            if contentFree(restricted) {
                return emptiable(base)
            }
            switch (restricted.term, base.term) {
            case let (.element(rName, _, rTypeName, rValue, rBlock, rNil), .element(bName, bType, bTypeName, bValue, bBlock, bNil)):
                // NameAndTypeOK: beyond name, occurrence, and type derivation, the
                // restriction's {disallowed substitutions} must be a superset of the
                // base's (it may block more, never fewer); if the base is fixed the
                // restriction must be fixed to the same value; and it may not be
                // nillable unless the base element is.
                return rangeSubsumed(restricted, base)
                    && sameName(rName, bName)
                    && rBlock.isSuperset(of: bBlock)
                    && (!rNil || bNil)
                    && fixedValueOK(rValue, bValue, bType, types)
                    && elementTypeRestrictionOK(rTypeName, bTypeName, types, derivation)
            case let (.element(name, _, _, _, _, _), .wildcard(wildcard)):
                return rangeSubsumed(restricted, base) && wildcard.admits(name)
            case let (.wildcard(restrictedWildcard), .wildcard(baseWildcard)):
                return rangeSubsumed(restricted, base) && narrows(restrictedWildcard, baseWildcard)
            case let (.element, .group(baseGroup)):
                return elementRestrictsGroup(restricted, base, baseGroup, types, derivation)
            case (.group, .element):
                // XSD 1.0 §3.9.6 "Particle Valid (Restriction)" defines NO case for a
                // derived group against a base element: the only element/group pairing
                // is the reverse (an element restricting a base group, via
                // RecurseAsIfGroup). A derived group that can contribute content
                // therefore never validly restricts a single base element, regardless
                // of how its leaves are named or counted. (A CONTENT-FREE derived group
                // was already accepted above as a valid restriction of any emptiable
                // base; only a content-bearing one reaches here.) This is the spec rule
                // the corpus enforces -- e.g. a `choice(seq(e1), e2, e3)` restricting a
                // `choice(e1, e2, e3)` is invalid because the derived `seq(e1)` branch
                // has no base element it can validly restrict (particlesHb011).
                return false
            case let (.group(restrictedGroup), .group(baseGroup)) where restrictedGroup.compositor == .sequence && baseGroup.compositor == .choice:
                // MapAndSum (Sequence:Choice, XSD 1.0 §3.9.6): each derived particle is
                // a valid restriction of some base branch, AND the derived sequence's
                // occurrence count times its number of particles is within the base
                // choice's occurrence range. The outer occurrence subsumption used by
                // the same-compositor cases is wrong here (it would compare a derived
                // `sequence{2,4}` directly to a base `choice{3,9}`); the count-product
                // is the spec's measure, deliberately stricter than a pure subset.
                let members = restrictedGroup.particles.filter { $0.maxOccurs != 0 }
                let branches = baseGroup.particles.filter { $0.maxOccurs != 0 }
                return rangeWithinWildcard(
                    derivedMin: restricted.minOccurs * members.count,
                    derivedMax: restricted.maxOccurs.map { $0 * members.count },
                    wildcardMin: base.minOccurs,
                    wildcardMax: base.maxOccurs,
                )
                    && members.allSatisfy { member in branches.contains { valid(member, $0, types, derivation) } }
            case let (.group(restrictedGroup), .group(baseGroup)):
                // A content-free derived group was already handled above; here the
                // derived group can contribute content, so its outer occurrence must be
                // subsumed and its members must map onto the base's.
                return rangeSubsumed(restricted, base) && groupValid(restrictedGroup, baseGroup, types, derivation)
            case let (.group, .wildcard(wildcard)):
                // NSRecurseCheckCardinality: every leaf the group can contain is
                // admitted by the wildcard (an element by name, a nested wildcard by
                // narrowing), AND the group's effective total occurrence range is
                // within the wildcard's occurrence range.
                return leavesAdmitted(restricted, by: wildcard)
                    && rangeWithinWildcard(
                        derivedMin: restricted.effectiveOccurrenceMin(),
                        derivedMax: restricted.effectiveOccurrenceMax(),
                        wildcardMin: base.minOccurs,
                        wildcardMax: base.maxOccurs,
                    )
            default:
                return false
            }
        }

        private static func groupValid(_ restricted: Group, _ base: Group, _ types: [String: ElementType], _ derivation: [String: TypeDerivation]) -> Bool {
            // A particle that can never occur (maxOccurs=0) contributes nothing to the
            // language, so it is removed before mapping (a "pointless particle"). Left
            // in, it would wrongly consume a base particle and starve the particles
            // after it (e.g. `(e1 maxOccurs=0, e2)` restricting `(any)`).
            let restrictedParticles = restricted.particles.filter { $0.maxOccurs != 0 }
            let baseParticles = base.particles.filter { $0.maxOccurs != 0 }
            switch (restricted.compositor, base.compositor) {
            case (.sequence, .sequence), (.all, .all):
                return recurse(restrictedParticles, baseParticles, skippedMustBeEmptiable: true, types, derivation)
            case (.choice, .choice):
                // RecurseLax: an order-preserving mapping (W3C requires it; a choice
                // `(b|a)` is NOT a valid restriction of `(a|b)`), but skipped base
                // branches need not be emptiable. The base's substitution-group
                // expansion must therefore be in document order for this to be right.
                return recurse(restrictedParticles, baseParticles, skippedMustBeEmptiable: false, types, derivation)
            case (.sequence, .choice):
                // RecurseAsIfGroup for an element against a base choice arrives here as a
                // one-particle synthetic sequence: each derived particle fits some base
                // branch. (A genuine multi-particle sequence restricting a choice is
                // handled by MapAndSum at the particle level, where the occurrence
                // count-product is available.)
                return restrictedParticles.allSatisfy { particle in
                    baseParticles.contains { valid(particle, $0, types, derivation) }
                }
            case (.sequence, .all):
                // RecurseUnordered: map onto distinct base particles in any order.
                return recurseUnordered(restrictedParticles, baseParticles, types, derivation)
            default:
                return false
            }
        }

        /// Whether a particle can never contribute a child element or wildcard: it
        /// has `maxOccurs=0`, or is a group all of whose members are content-free
        /// (an empty group included). Its only legal content is the empty sequence.
        static func contentFree(_ particle: Particle) -> Bool {
            if particle.maxOccurs == 0 { return true }
            switch particle.term {
            case .element, .wildcard:
                return false
            case let .group(group):
                return group.particles.allSatisfy(contentFree)
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
        /// Whether `restricted` is a valid subset of `base` (Wildcard Subset): its
        /// processContents is at least as strong and its namespace constraint is
        /// narrower or equal. Shared with attribute-wildcard restriction.
        static func narrows(_ restricted: Wildcard, _ base: Wildcard) -> Bool {
            // Wildcard Subset (XSD 1.0 §3.10.6): the restriction's processContents
            // must be identical to or STRONGER than the base's (strict > lax > skip);
            // a restriction may not weaken validation. Namespace narrowing is below.
            guard processContentsRank(restricted.processContents) >= processContentsRank(base.processContents) else {
                return false
            }
            // Wildcard Subset (XSD 1.0 §3.10.6 / Errata E1-10): the restriction's
            // namespace constraint must admit only what the base does. Both `not`
            // forms exclude absent.
            return switch (restricted.namespace, base.namespace) {
            case (_, .any):
                true
            case let (.enumerated(narrow), .enumerated(wide)):
                narrow.isSubset(of: wide)
            case let (.enumerated(narrow), .notNamespace(excluded)):
                !narrow.contains(excluded) && !narrow.contains("")
            case let (.enumerated(narrow), .notAbsent):
                !narrow.contains("")
            case let (.notNamespace(narrow), .notNamespace(wide)):
                narrow == wide
            case (.notNamespace, .notAbsent), (.notAbsent, .notAbsent):
                true
            default:
                false
            }
        }

        private static func sameName(_ lhs: PureXML.Model.QualifiedName, _ rhs: PureXML.Model.QualifiedName) -> Bool {
            lhs.localName == rhs.localName && (lhs.namespaceURI ?? "") == (rhs.namespaceURI ?? "")
        }

        /// RecurseAsIfGroup against a CHOICE, read by effective total range. The
        /// literal §3.9.6 rule under-approximates the ground truth (derived language ⊆
        /// base language) and over-rejects a repeating base choice (particlesZ001, whose
        /// test doc calls the rule "ambiguous"; W3C reads it valid). First principles:
        /// the element validly restricts the choice iff its leaf is a NameAndTypeOK
        /// restriction of some element the choice admits AND its effective occurrence
        /// range is within the choice's. Accepts `element{0,∞}` over `choice{0,∞}(...)`
        /// (Z001) and `c1{2,2}` over a choice whose branch holds `c1` (M002/003); a
        /// must-repeat choice (effective min ≥ 2) still rejects a single element
        /// (particlesL). A documented, bounded under-rejection (exact in-branch
        /// sequencing is not modelled); over-rejection is the non-starter.
        private static func elementRestrictsGroup(
            _ restricted: Particle,
            _ base: Particle,
            _ baseGroup: Group,
            _ types: [String: ElementType],
            _ derivation: [String: TypeDerivation],
        ) -> Bool {
            if baseGroup.compositor == .choice {
                return elementRestrictsChoice(restricted, base, baseGroup, types, derivation)
            }
            // RecurseAsIfGroup for a sequence/all base (§3.9.6): the element as a
            // {1,1} synthetic group must be within the base group's range and map to
            // a base member inside `groupValid`.
            return rangeWithinWildcard(derivedMin: 1, derivedMax: 1, wildcardMin: base.minOccurs, wildcardMax: base.maxOccurs)
                && groupValid(Group(compositor: .sequence, particles: [restricted]), baseGroup, types, derivation)
        }

        private static func elementRestrictsChoice(
            _ restricted: Particle,
            _ base: Particle,
            _ baseGroup: Group,
            _ types: [String: ElementType],
            _ derivation: [String: TypeDerivation],
        ) -> Bool {
            let neutral = Particle(minOccurs: 1, maxOccurs: 1, term: restricted.term)
            let admitted = elementLeaves(of: baseGroup).contains {
                valid(neutral, Particle(minOccurs: 1, maxOccurs: 1, term: $0), types, derivation)
            }
            return admitted
                && rangeWithinWildcard(
                    derivedMin: restricted.effectiveOccurrenceMin(),
                    derivedMax: restricted.effectiveOccurrenceMax(),
                    wildcardMin: base.effectiveOccurrenceMin(),
                    wildcardMax: base.effectiveOccurrenceMax(),
                )
        }

        /// Whether every leaf a particle can contain is admitted by `wildcard`: an
        /// element by name, a nested wildcard by narrowing.
        private static func leavesAdmitted(_ particle: Particle, by wildcard: Wildcard) -> Bool {
            switch particle.term {
            case let .element(name, _, _, _, _, _): wildcard.admits(name)
            case let .wildcard(inner): narrows(inner, wildcard)
            case let .group(group): group.particles.allSatisfy { leavesAdmitted($0, by: wildcard) }
            }
        }

        /// Whether a derived effective total range fits within a base wildcard's
        /// occurrence range: at least the wildcard's minimum, at most its maximum.
        private static func rangeWithinWildcard(derivedMin: Int, derivedMax: Int?, wildcardMin: Int, wildcardMax: Int?) -> Bool {
            guard derivedMin >= wildcardMin else { return false }
            guard let wildcardMax else { return true }
            guard let derivedMax else { return false }
            return derivedMax <= wildcardMax
        }
    }
}
