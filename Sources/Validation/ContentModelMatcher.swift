extension PureXML.Validation {
    /// Matches a sequence of child element names against a content-model particle.
    /// A content model is a regular expression over child element names, so this
    /// is an NFA-style matcher: it tracks the set of positions reachable in the
    /// name sequence, and the whole sequence matches when the end is reachable.
    enum ContentModelMatcher {
        static func matchesChildren(_ particle: Particle, _ names: [String]) -> Bool {
            advance(particle, names, from: [0]).contains(names.count)
        }

        /// Every element name the content model can contain (its alphabet), used to
        /// tell a stray child from one that is merely out of order or count.
        static func allowedNames(_ particle: Particle) -> Set<String> {
            switch particle {
            case let .name(name, _):
                [name]
            case let .sequence(items, _), let .choice(items, _):
                items.reduce(into: Set<String>()) { $0.formUnion(allowedNames($1)) }
            }
        }

        /// End positions reachable by matching `particle` (with its occurrence)
        /// once from each given start position.
        private static func advance(_ particle: Particle, _ names: [String], from starts: Set<Int>) -> Set<Int> {
            switch occurrence(of: particle) {
            case .once:
                return starts.reduce(into: Set<Int>()) { $0.formUnion(matchOnce(particle, names, from: $1)) }
            case .optional:
                var result = starts
                for start in starts {
                    result.formUnion(matchOnce(particle, names, from: start))
                }
                return result
            case .zeroOrMore:
                return closure(particle, names, starts, includingStarts: true)
            case .oneOrMore:
                return closure(particle, names, starts, includingStarts: false)
            }
        }

        /// End positions from matching the particle's structure exactly once,
        /// ignoring its own occurrence (which ``advance(_:_:from:)`` applies).
        private static func matchOnce(_ particle: Particle, _ names: [String], from start: Int) -> Set<Int> {
            switch particle {
            case let .name(name, _):
                return start < names.count && names[start] == name ? [start + 1] : []
            case let .sequence(items, _):
                var positions: Set<Int> = [start]
                for item in items {
                    positions = positions.reduce(into: Set<Int>()) { $0.formUnion(advance(item, names, from: [$1])) }
                }
                return positions
            case let .choice(items, _):
                return items.reduce(into: Set<Int>()) { $0.formUnion(advance($1, names, from: [start])) }
            }
        }

        private static func closure(
            _ particle: Particle,
            _ names: [String],
            _ starts: Set<Int>,
            includingStarts: Bool,
        ) -> Set<Int> {
            var result = includingStarts ? starts : Set<Int>()
            var frontier = starts
            while !frontier.isEmpty {
                var next: Set<Int> = []
                for position in frontier {
                    for end in matchOnce(particle, names, from: position) where !result.contains(end) {
                        next.insert(end)
                    }
                }
                result.formUnion(next)
                frontier = next
            }
            return result
        }

        private static func occurrence(of particle: Particle) -> Occurrence {
            switch particle {
            case let .name(_, occurrence), let .sequence(_, occurrence), let .choice(_, occurrence):
                occurrence
            }
        }
    }
}
