extension PureXML.Schema {
    /// A transition label in the content-model automaton: a specific expanded
    /// element name, or a wildcard.
    enum TermLabel: Sendable {
        case name(PureXML.Model.QualifiedName)
        case wildcard(Wildcard)

        func matches(_ actual: PureXML.Model.QualifiedName) -> Bool {
            switch self {
            case let .wildcard(wildcard): wildcard.admits(actual)
            case let .name(declared): declared.localName == actual.localName
                && declared.namespaceURI == actual.namespaceURI
            }
        }
    }

    /// One state of the content-model automaton.
    struct ContentState: Sendable {
        var epsilon: [Int] = []
        var label: TermLabel?
        var target: Int?
    }

    /// A Thompson NFA over element names compiled from a ``Particle``. `all` groups
    /// are validated separately by ``ContentMatcher`` and are not represented here.
    struct ContentNFA: Sendable {
        var states: [ContentState]
        var start: Int
        var accept: Int

        func matchesWhole(_ names: [PureXML.Model.QualifiedName]) -> Bool {
            var current = closure([start])
            for name in names {
                var next: Set<Int> = []
                for state in current {
                    if let label = states[state].label, let target = states[state].target, label.matches(name) {
                        next.insert(target)
                    }
                }
                if next.isEmpty { return false }
                current = closure(next)
            }
            return current.contains(accept)
        }

        /// After consuming `names`, the labels the automaton can accept next and
        /// whether the content may legally end here. The follow-set: the exact set
        /// of element names allowed at this point, for completions and for telling
        /// whether something is still required. Returns an empty, not-complete
        /// result when the prefix is already invalid.
        func follow(after names: [PureXML.Model.QualifiedName]) -> (allowed: [TermLabel], complete: Bool) {
            var current = closure([start])
            for name in names {
                var next: Set<Int> = []
                for state in current {
                    if let label = states[state].label, let target = states[state].target, label.matches(name) {
                        next.insert(target)
                    }
                }
                if next.isEmpty { return ([], false) }
                current = closure(next)
            }
            var labels: [TermLabel] = []
            for state in current where states[state].target != nil {
                if let label = states[state].label { labels.append(label) }
            }
            return (labels, current.contains(accept))
        }

        private func closure(_ seed: Set<Int>) -> Set<Int> {
            var seen = seed
            var stack = Array(seed)
            while let state = stack.popLast() {
                for next in states[state].epsilon where seen.insert(next).inserted {
                    stack.append(next)
                }
            }
            return seen
        }
    }

    /// Builds a ``ContentNFA`` from a particle by Thompson construction.
    struct ContentNFABuilder {
        private var states: [ContentState] = []

        static func build(_ particle: PureXML.Schema.Particle) -> ContentNFA {
            var builder = ContentNFABuilder()
            let fragment = builder.particle(particle)
            return ContentNFA(states: builder.states, start: fragment.start, accept: fragment.accept)
        }

        private mutating func addState() -> Int {
            states.append(ContentState())
            return states.count - 1
        }

        /// Occurrence counts unroll into automaton states, so they are
        /// capped: beyond the cap a repetition is treated as unbounded, the
        /// libxml2 posture (its cap is 16384). Without this, a schema with
        /// maxOccurs in the trillions allocates until the process dies
        /// (found by XSTS groupF009v, #129).
        private static let occursUnrollCap = 16384

        private mutating func particle(_ particle: PureXML.Schema.Particle) -> (start: Int, accept: Int) {
            let start = addState()
            var current = start
            let boundedMin = Swift.min(particle.minOccurs, Self.occursUnrollCap)
            for _ in 0 ..< boundedMin {
                let part = term(particle.term)
                states[current].epsilon.append(part.start)
                current = part.accept
            }
            let accept = addState()
            if particle.minOccurs > Self.occursUnrollCap {
                // The tail of an absurd minOccurs is approximated as star.
                appendStar(particle.term, from: current, to: accept)
            } else if let maximum = particle.maxOccurs, maximum - boundedMin <= Self.occursUnrollCap {
                appendOptional(particle.term, count: maximum - boundedMin, from: current, to: accept)
            } else {
                appendStar(particle.term, from: current, to: accept)
            }
            return (start, accept)
        }

        private mutating func appendOptional(_ term: PureXML.Schema.Term, count: Int, from: Int, to accept: Int) {
            var current = from
            for _ in 0 ..< Swift.max(0, count) {
                let part = self.term(term)
                states[current].epsilon.append(part.start)
                states[current].epsilon.append(accept)
                current = part.accept
            }
            states[current].epsilon.append(accept)
        }

        private mutating func appendStar(_ term: PureXML.Schema.Term, from current: Int, to accept: Int) {
            let part = self.term(term)
            states[current].epsilon.append(part.start)
            states[current].epsilon.append(accept)
            states[part.accept].epsilon.append(part.start)
            states[part.accept].epsilon.append(accept)
        }

        private mutating func term(_ term: PureXML.Schema.Term) -> (start: Int, accept: Int) {
            switch term {
            case let .element(name, _):
                labeled(.name(name))
            case let .wildcard(wildcard):
                labeled(.wildcard(wildcard))
            case let .group(group):
                self.group(group)
            }
        }

        private mutating func labeled(_ label: TermLabel) -> (start: Int, accept: Int) {
            let start = addState()
            let accept = addState()
            states[start].label = label
            states[start].target = accept
            return (start, accept)
        }

        private mutating func group(_ group: PureXML.Schema.Group) -> (start: Int, accept: Int) {
            // `all` is validated by counting, not in the NFA; treat it as a
            // sequence here so a nested occurrence still parses.
            group.compositor == .choice ? choice(group.particles) : sequence(group.particles)
        }

        private mutating func sequence(_ particles: [PureXML.Schema.Particle]) -> (start: Int, accept: Int) {
            guard !particles.isEmpty else { return labeledEmpty() }
            var first: Int?
            var last: Int?
            for member in particles {
                let part = particle(member)
                if let previous = last { states[previous].epsilon.append(part.start) } else { first = part.start }
                last = part.accept
            }
            return (first ?? addState(), last ?? addState())
        }

        private mutating func choice(_ particles: [PureXML.Schema.Particle]) -> (start: Int, accept: Int) {
            let start = addState()
            let accept = addState()
            for member in particles {
                let part = particle(member)
                states[start].epsilon.append(part.start)
                states[part.accept].epsilon.append(accept)
            }
            return (start, accept)
        }

        private mutating func labeledEmpty() -> (start: Int, accept: Int) {
            let start = addState()
            let accept = addState()
            states[start].epsilon.append(accept)
            return (start, accept)
        }
    }
}
