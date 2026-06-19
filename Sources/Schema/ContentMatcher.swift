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

    /// A guard on a counted epsilon transition.
    enum ContentCounterGuard: Sendable {
        case canExit(counter: Int, minimum: NonNegativeDecimal, nullableBody: Bool)
        case belowMaximum(counter: Int, maximum: OccurrenceUpper)

        func accepts(_ values: [Int]) -> Bool {
            switch self {
            case let .canExit(counter, minimum, nullableBody):
                nullableBody || minimum.isLessThanOrEqual(to: values[counter])
            case let .belowMaximum(counter, maximum):
                maximum.isGreaterThan(values[counter])
            }
        }
    }

    /// An action on a counted epsilon transition.
    enum ContentCounterAction: Sendable {
        case reset(Int)
        case increment(Int)

        func apply(to values: inout [Int], limit: Int) {
            switch self {
            case let .reset(counter):
                values[counter] = 0
            case let .increment(counter):
                if values[counter] < limit {
                    values[counter] += 1
                }
            }
        }
    }

    /// One epsilon transition in the counted content-model automaton.
    struct ContentEpsilonEdge: Sendable {
        var target: Int
        var guards: [ContentCounterGuard] = []
        var actions: [ContentCounterAction] = []
    }

    /// One occurrence counter in the counted content-model automaton.
    struct ContentCounterScope: Sendable {
        var range: OccurrenceRange
        var nullableBody: Bool
    }

    /// One state of the counted content-model automaton.
    struct ContentState: Sendable {
        var epsilon: [ContentEpsilonEdge] = []
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

    /// One active configuration in the counted content-model automaton.
    struct ContentConfiguration: Sendable, Hashable {
        var state: Int
        var counters: [Int]
    }

    /// A counted automaton over element names compiled from a ``Particle``. `all`
    /// groups are validated separately by ``ContentMatcher`` and are not represented
    /// here.
    struct ContentNFA: Sendable {
        var states: [ContentState]
        var counters: [ContentCounterScope]
        var start: Int
        var accept: Int

        func matchesWhole(_ names: [PureXML.Model.QualifiedName]) -> Bool {
            let inputLength = names.count
            var current = startStates(inputLength: inputLength)
            for name in names {
                guard let next = step(current, over: name, inputLength: inputLength) else { return false }
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
            let inputLength = names.count
            var current = startStates(inputLength: inputLength)
            for name in names {
                guard let next = step(current, over: name, inputLength: inputLength) else { return ([], false) }
                current = next
            }
            return (admissible(from: current), isComplete(current))
        }

        // MARK: Incremental matching

        //
        // The active set is the epsilon-closure of the configurations reachable after some
        // prefix of children. Callers that scan a child sequence advance it one
        // child at a time (`startStates` then `step` per child) rather than calling
        // `follow(after:)` on a growing prefix, which re-walks the whole prefix each
        // time and is quadratic in the child count over a content model (#129).

        /// The active set before any child: the closure of the start state.
        func startStates(inputLength: Int = 0) -> Set<ContentConfiguration> {
            let seed = ContentConfiguration(state: start, counters: Array(repeating: 0, count: counters.count))
            return closure([seed], counterLimit: counterLimit(for: inputLength))
        }

        /// The labels admissible from `current`, for diagnostics and completions.
        func admissible(from current: Set<ContentConfiguration>) -> [TermLabel] {
            var labels: [TermLabel] = []
            for configuration in current where states[configuration.state].target != nil {
                if let label = states[configuration.state].label { labels.append(label) }
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
            let inputLength = names.count
            var current = startStates(inputLength: inputLength)
            var result: [MatchedParticle?] = []
            for name in names {
                var next: Set<ContentConfiguration> = []
                var namedMatch: ContentConfiguration?
                var namedState: Int?
                var anyMatch: ContentConfiguration?
                var anyState: Int?
                for configuration in current {
                    let state = configuration.state
                    guard let label = states[state].label, let target = states[state].target, label.matches(name) else { continue }
                    next.insert(ContentConfiguration(state: target, counters: configuration.counters))
                    if anyState.map({ state < $0 }) ?? true {
                        anyState = state
                        anyMatch = configuration
                    }
                    if case .name = label, namedState.map({ state < $0 }) ?? true {
                        namedState = state
                        namedMatch = configuration
                    }
                }
                guard let chosenState = namedState ?? anyState, (namedMatch ?? anyMatch) != nil, !next.isEmpty else {
                    result.append(contentsOf: Array(repeating: nil, count: names.count - result.count))
                    return result
                }
                let matched = states[chosenState]
                if case let .wildcard(wildcard) = matched.label {
                    result.append(.wildcard(wildcard))
                } else {
                    result.append(.element(type: matched.elementType, valueConstraint: matched.valueConstraint))
                }
                current = closure(next, counterLimit: counterLimit(for: inputLength))
            }
            return result
        }

        /// Advances `current` by consuming one element `name`, or nil when `name`
        /// is not admissible there.
        func step(_ current: Set<ContentConfiguration>, over name: PureXML.Model.QualifiedName, inputLength: Int = 0) -> Set<ContentConfiguration>? {
            var next: Set<ContentConfiguration> = []
            for configuration in current {
                let state = configuration.state
                if let label = states[state].label, let target = states[state].target, label.matches(name) {
                    next.insert(ContentConfiguration(state: target, counters: configuration.counters))
                }
            }
            if next.isEmpty { return nil }
            return closure(next, counterLimit: counterLimit(for: inputLength))
        }

        /// Whether the content may legally end at `current`.
        func isComplete(_ current: Set<ContentConfiguration>) -> Bool {
            current.contains { $0.state == accept }
        }

        private func closure(_ seed: Set<ContentConfiguration>, counterLimit: Int) -> Set<ContentConfiguration> {
            var seen = seed
            var stack = Array(seed)
            while let configuration = stack.popLast() {
                for edge in states[configuration.state].epsilon {
                    guard let next = apply(edge, to: configuration, counterLimit: counterLimit),
                          seen.insert(next).inserted
                    else {
                        continue
                    }
                    stack.append(next)
                }
            }
            return seen
        }

        private func apply(
            _ edge: ContentEpsilonEdge,
            to configuration: ContentConfiguration,
            counterLimit: Int,
        ) -> ContentConfiguration? {
            for guardCondition in edge.guards where !guardCondition.accepts(configuration.counters) {
                return nil
            }
            var values = configuration.counters
            for action in edge.actions {
                action.apply(to: &values, limit: counterLimit)
            }
            return ContentConfiguration(state: edge.target, counters: values)
        }

        private func counterLimit(for inputLength: Int) -> Int {
            inputLength == Int.max ? Int.max : inputLength + 1
        }
    }
}
