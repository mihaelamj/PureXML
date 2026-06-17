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
        /// The declared type and value constraint of the element particle this
        /// state's `.name` transition stands for, carried so that whoever the
        /// automaton matches a child to can be assessed against that exact
        /// particle (its type, its `fixed`/`default`), not a by-name lookup that
        /// cannot tell two same-named particles apart.
        var elementType: ElementType?
        var valueConstraint: ValueConstraint?
    }

    /// The content-model particle a child was matched to, for per-child
    /// assessment: a named element (with the particle's declared type and value
    /// constraint) or a wildcard (carrying its `processContents`).
    enum MatchedParticle: Sendable {
        case element(type: ElementType?, valueConstraint: ValueConstraint?)
        case wildcard(Wildcard)
    }

    /// A Thompson NFA over element names compiled from a ``Particle``. `all` groups
    /// are validated separately by ``ContentMatcher`` and are not represented here.
    struct ContentNFA: Sendable {
        var states: [ContentState]
        var start: Int
        var accept: Int

        func matchesWhole(_ names: [PureXML.Model.QualifiedName]) -> Bool {
            var current = startStates()
            for name in names {
                guard let next = step(current, over: name) else { return false }
                current = next
            }
            return isComplete(current)
        }

        /// After consuming `names`, the labels the automaton can accept next and
        /// whether the content may legally end here. The follow-set: the exact set
        /// of element names allowed at this point, for completions and for telling
        /// whether something is still required. Returns an empty, not-complete
        /// result when the prefix is already invalid.
        func follow(after names: [PureXML.Model.QualifiedName]) -> (allowed: [TermLabel], complete: Bool) {
            var current = startStates()
            for name in names {
                guard let next = step(current, over: name) else { return ([], false) }
                current = next
            }
            return (admissible(from: current), isComplete(current))
        }

        // MARK: Incremental matching

        //
        // The active set is the epsilon-closure of the states reachable after some
        // prefix of children. Callers that scan a child sequence advance it one
        // child at a time (`startStates` then `step` per child) rather than calling
        // `follow(after:)` on a growing prefix, which re-walks the whole prefix each
        // time and is quadratic in the child count over a content model (#129).

        /// The active set before any child: the closure of the start state.
        func startStates() -> Set<Int> {
            closure([start])
        }

        /// The labels admissible from `current`, for diagnostics and completions.
        func admissible(from current: Set<Int>) -> [TermLabel] {
            var labels: [TermLabel] = []
            for state in current where states[state].target != nil {
                if let label = states[state].label { labels.append(label) }
            }
            return labels
        }

        /// The particle each child matched, in order, for per-child assessment.
        /// A unique-particle-attribution-valid content model is deterministic, so
        /// at each position at most one particle accepts the child; the entry is
        /// nil from the first child the model rejects onward (a structure error,
        /// reported separately), since the match path is then undefined.
        ///
        /// When more than one active state accepts the child (only possible if the
        /// compile-time UPA check missed an ambiguity), selection is still made
        /// reproducible rather than left to `Set` iteration order: a named particle
        /// is preferred over a wildcard, then the lowest state index wins.
        func matchedParticles(_ names: [PureXML.Model.QualifiedName]) -> [MatchedParticle?] {
            var current = startStates()
            var result: [MatchedParticle?] = []
            for name in names {
                var next: Set<Int> = []
                var namedMatch: Int?
                var anyMatch: Int?
                for state in current {
                    guard let label = states[state].label, let target = states[state].target, label.matches(name) else { continue }
                    next.insert(target)
                    if anyMatch.map({ state < $0 }) ?? true { anyMatch = state }
                    if case .name = label, namedMatch.map({ state < $0 }) ?? true { namedMatch = state }
                }
                guard let chosen = namedMatch ?? anyMatch, !next.isEmpty else {
                    result.append(contentsOf: Array(repeating: nil, count: names.count - result.count))
                    return result
                }
                let matched = states[chosen]
                if case let .wildcard(wildcard) = matched.label {
                    result.append(.wildcard(wildcard))
                } else {
                    result.append(.element(type: matched.elementType, valueConstraint: matched.valueConstraint))
                }
                current = closure(next)
            }
            return result
        }

        /// Advances `current` by consuming one element `name`, or nil when `name`
        /// is not admissible there.
        func step(_ current: Set<Int>, over name: PureXML.Model.QualifiedName) -> Set<Int>? {
            var next: Set<Int> = []
            for state in current {
                if let label = states[state].label, let target = states[state].target, label.matches(name) {
                    next.insert(target)
                }
            }
            if next.isEmpty { return nil }
            return closure(next)
        }

        /// Whether the content may legally end at `current`.
        func isComplete(_ current: Set<Int>) -> Bool {
            current.contains(accept)
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

        /// The per-particle cap bounds one repetition, but nested particles
        /// multiply: a sequence of 16384 holding a choice of 16384 is 2.7e8
        /// states even though each particle is individually capped. So the
        /// total state count is also capped; once an NFA reaches the ceiling
        /// every further repetition degrades to star, the same posture the
        /// per-particle cap already takes. Legitimate content models are tens
        /// of states, so only the pathological XSTS particle schemas (the
        /// msMeta Particles set, which OOM-killed the suite at 8 GB, #129)
        /// reach it. The ceiling sits well above a single maxed particle
        /// (~33k states) so capped-but-not-nested schemas are unaffected.
        private static let totalStateCap = 1 << 20

        private var stateBudgetExhausted: Bool {
            states.count >= Self.totalStateCap
        }

        private mutating func particle(_ particle: PureXML.Schema.Particle) -> (start: Int, accept: Int) {
            let start = addState()
            var current = start
            let boundedMin = Swift.min(particle.minOccurs, Self.occursUnrollCap)
            var unrolledMin = 0
            for _ in 0 ..< boundedMin {
                if stateBudgetExhausted { break }
                let part = term(particle.term)
                states[current].epsilon.append(part.start)
                current = part.accept
                unrolledMin += 1
            }
            let accept = addState()
            if stateBudgetExhausted || unrolledMin < boundedMin || particle.minOccurs > Self.occursUnrollCap {
                // The tail of an absurd minOccurs, or a run that hit the total
                // state ceiling mid-unroll, is approximated as star.
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
                if stateBudgetExhausted {
                    // Ran out of state budget: let the remainder repeat freely
                    // (star) rather than keep allocating bounded optionals.
                    appendStar(term, from: current, to: accept)
                    return
                }
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
            case let .element(name, type, _, constraint, _, _):
                let fragment = labeled(.name(name))
                states[fragment.start].elementType = type
                states[fragment.start].valueConstraint = constraint
                return fragment
            case let .wildcard(wildcard):
                return labeled(.wildcard(wildcard))
            case let .group(group):
                return self.group(group)
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
