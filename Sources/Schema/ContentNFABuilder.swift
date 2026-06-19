extension PureXML.Schema {
    struct ContentNFAFragment {
        var start: Int
        var accept: Int
        var counters: [Int]
        var nullable: Bool
    }

    /// Builds a counted ``ContentNFA`` from a particle.
    struct ContentNFABuilder {
        private var states: [ContentState] = []
        private var counters: [ContentCounterScope] = []

        static func build(_ particle: PureXML.Schema.Particle) -> ContentNFA {
            var builder = ContentNFABuilder()
            let fragment = builder.particle(particle)
            return ContentNFA(
                states: builder.states,
                counters: builder.counters,
                start: fragment.start,
                accept: fragment.accept,
            )
        }

        private mutating func addState() -> Int {
            states.append(ContentState())
            return states.count - 1
        }

        private mutating func addEpsilon(
            from source: Int,
            to target: Int,
            guards: [ContentCounterGuard] = [],
            actions: [ContentCounterAction] = [],
        ) {
            states[source].epsilon.append(ContentEpsilonEdge(target: target, guards: guards, actions: actions))
        }

        private mutating func particle(_ particle: PureXML.Schema.Particle) -> ContentNFAFragment {
            let start = addState()
            let loop = addState()
            let accept = addState()
            let counter = counters.count
            let bodyNullable = termIsNullable(particle.term)
            counters.append(ContentCounterScope(range: particle.occurrenceRange, nullableBody: bodyNullable))
            let body = term(particle.term)
            let resetAll = [ContentCounterAction.reset(counter)] + body.counters.map(ContentCounterAction.reset)
            addEpsilon(from: start, to: loop, actions: resetAll)
            addEpsilon(
                from: loop,
                to: accept,
                guards: [
                    .canExit(
                        counter: counter,
                        minimum: particle.occurrenceRange.minimum,
                        nullableBody: bodyNullable,
                    ),
                ],
            )
            addEpsilon(
                from: loop,
                to: body.start,
                guards: [.belowMaximum(counter: counter, maximum: particle.occurrenceRange.maximum)],
                actions: body.counters.map(ContentCounterAction.reset),
            )
            addEpsilon(from: body.accept, to: loop, actions: [.increment(counter)])
            return ContentNFAFragment(
                start: start,
                accept: accept,
                counters: [counter] + body.counters,
                nullable: particleIsNullable(particle),
            )
        }

        private mutating func term(_ term: PureXML.Schema.Term) -> ContentNFAFragment {
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

        private mutating func labeled(_ label: TermLabel) -> ContentNFAFragment {
            let start = addState()
            let accept = addState()
            states[start].label = label
            states[start].target = accept
            return ContentNFAFragment(start: start, accept: accept, counters: [], nullable: false)
        }

        private mutating func group(_ group: PureXML.Schema.Group) -> ContentNFAFragment {
            // `all` is validated by counting, not in the NFA; treat it as a
            // sequence here so a nested occurrence still parses.
            group.compositor == .choice ? choice(group.particles) : sequence(group.particles)
        }

        private mutating func sequence(_ particles: [PureXML.Schema.Particle]) -> ContentNFAFragment {
            guard !particles.isEmpty else { return labeledEmpty() }
            var first: Int?
            var last: Int?
            var fragmentCounters: [Int] = []
            var nullable = true
            for member in particles {
                let part = particle(member)
                if let previous = last { addEpsilon(from: previous, to: part.start) } else { first = part.start }
                last = part.accept
                fragmentCounters.append(contentsOf: part.counters)
                nullable = nullable && part.nullable
            }
            return ContentNFAFragment(
                start: first ?? addState(),
                accept: last ?? addState(),
                counters: fragmentCounters,
                nullable: nullable,
            )
        }

        private mutating func choice(_ particles: [PureXML.Schema.Particle]) -> ContentNFAFragment {
            let start = addState()
            let accept = addState()
            var fragmentCounters: [Int] = []
            var nullable = false
            for member in particles {
                let part = particle(member)
                addEpsilon(from: start, to: part.start)
                addEpsilon(from: part.accept, to: accept)
                fragmentCounters.append(contentsOf: part.counters)
                nullable = nullable || part.nullable
            }
            return ContentNFAFragment(
                start: start,
                accept: accept,
                counters: fragmentCounters,
                nullable: nullable,
            )
        }

        private mutating func labeledEmpty() -> ContentNFAFragment {
            let start = addState()
            let accept = addState()
            addEpsilon(from: start, to: accept)
            return ContentNFAFragment(start: start, accept: accept, counters: [], nullable: true)
        }

        private func particleIsNullable(_ particle: PureXML.Schema.Particle) -> Bool {
            particle.occurrenceRange.minimum.isZero || termIsNullable(particle.term)
        }

        private func termIsNullable(_ term: PureXML.Schema.Term) -> Bool {
            switch term {
            case .element, .wildcard:
                false
            case let .group(group):
                switch group.compositor {
                case .sequence, .all:
                    group.particles.allSatisfy(particleIsNullable)
                case .choice:
                    group.particles.contains(where: particleIsNullable)
                }
            }
        }
    }
}
