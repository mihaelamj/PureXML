extension PureXML.Schema.Particle {
    /// Eliminates pointless particles so the restriction algorithm sees the spec's
    /// normalized content model: a `maxOccurs=0` member contributes nothing and is
    /// dropped; a nested same-compositor `{1,1}` group is spliced into its parent;
    /// a `{1,1}` group with a single member is unwrapped to that member.
    /// Language-preserving.
    func normalized() -> Self {
        guard case let .group(group) = term else { return self }
        var members: [Self] = []
        for child in group.particles {
            let normalized = child.normalized()
            if normalized.maxOccurs == 0 { continue }
            let splice = normalized.minOccurs == 1 && normalized.maxOccurs == 1
            if case let .group(inner) = normalized.term, inner.compositor == group.compositor, splice {
                members.append(contentsOf: inner.particles)
            } else {
                members.append(normalized)
            }
        }
        if members.count == 1, minOccurs == 1, maxOccurs == 1 {
            return members[0]
        }
        return Self(minOccurs: minOccurs, maxOccurs: maxOccurs, term: .group(.init(compositor: group.compositor, particles: members)))
    }

    /// The minimum number of elements this particle can contribute (effective total
    /// range, lower bound): a leaf is its `minOccurs`; a sequence/all sums its
    /// members, a choice takes the smallest; times the particle's own `minOccurs`.
    func effectiveOccurrenceMin() -> Int {
        switch term {
        case .element, .wildcard:
            return minOccurs
        case let .group(group):
            let inner: Int = switch group.compositor {
            case .choice: group.particles.map { $0.effectiveOccurrenceMin() }.min() ?? 0
            case .sequence, .all: group.particles.map { $0.effectiveOccurrenceMin() }.reduce(0, +)
            }
            return minOccurs * inner
        }
    }

    /// The maximum number of elements this particle can contribute (nil = unbounded).
    func effectiveOccurrenceMax() -> Int? {
        switch term {
        case .element, .wildcard:
            return maxOccurs
        case let .group(group):
            let childMaxes = group.particles.map { $0.effectiveOccurrenceMax() }
            guard let particleMax = maxOccurs, !childMaxes.contains(where: { $0 == nil }) else { return nil }
            let maxes = childMaxes.compactMap(\.self)
            let inner = group.compositor == .choice ? (maxes.max() ?? 0) : maxes.reduce(0, +)
            return particleMax * inner
        }
    }
}
