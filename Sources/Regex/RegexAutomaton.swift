extension PureXML.Regex {
    /// One NFA state: epsilon transitions and at most one character-class
    /// transition (Thompson construction).
    struct NFAState: Sendable {
        var epsilon: [Int] = []
        var transition: CharTransition?
    }

    /// A character-consuming transition to another state.
    struct CharTransition: Sendable {
        let charClass: CharClass
        let target: Int
    }

    /// A compiled non-deterministic finite automaton.
    struct NFA: Sendable {
        var states: [NFAState]
        var start: Int
        var accept: Int

        /// Whether the automaton matches the whole string (XSD patterns are
        /// implicitly anchored at both ends).
        func matchesWhole(_ string: String) -> Bool {
            var current = closure([start])
            for character in string {
                var next: Set<Int> = []
                for state in current {
                    if let transition = states[state].transition, transition.charClass.matches(character) {
                        next.insert(transition.target)
                    }
                }
                if next.isEmpty { return false }
                current = closure(next)
            }
            return current.contains(accept)
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

    /// Builds an ``NFA`` from a ``Node`` by Thompson construction.
    struct NFABuilder {
        private var states: [NFAState] = []

        static func build(_ node: Node) -> NFA {
            var builder = NFABuilder()
            let fragment = builder.fragment(for: node)
            return NFA(states: builder.states, start: fragment.start, accept: fragment.accept)
        }

        private mutating func addState() -> Int {
            states.append(NFAState())
            return states.count - 1
        }

        private mutating func fragment(for node: Node) -> (start: Int, accept: Int) {
            switch node {
            case .empty:
                let start = addState()
                let accept = addState()
                states[start].epsilon.append(accept)
                return (start, accept)
            case let .characters(charClass):
                let start = addState()
                let accept = addState()
                states[start].transition = CharTransition(charClass: charClass, target: accept)
                return (start, accept)
            case let .concat(nodes):
                return concatenate(nodes)
            case let .alternate(nodes):
                return alternate(nodes)
            case let .repeated(inner, minimum, maximum):
                return repeatedFragment(inner, minimum: minimum, maximum: maximum)
            }
        }

        private mutating func concatenate(_ nodes: [Node]) -> (start: Int, accept: Int) {
            guard !nodes.isEmpty else { return fragment(for: .empty) }
            var first: Int?
            var last: Int?
            for node in nodes {
                let part = fragment(for: node)
                if let previous = last { states[previous].epsilon.append(part.start) } else { first = part.start }
                last = part.accept
            }
            return (first ?? addState(), last ?? addState())
        }

        private mutating func alternate(_ nodes: [Node]) -> (start: Int, accept: Int) {
            let start = addState()
            let accept = addState()
            for node in nodes {
                let part = fragment(for: node)
                states[start].epsilon.append(part.start)
                states[part.accept].epsilon.append(accept)
            }
            return (start, accept)
        }

        private mutating func repeatedFragment(_ node: Node, minimum: Int, maximum: Int?) -> (start: Int, accept: Int) {
            let start = addState()
            var current = start
            for _ in 0 ..< minimum {
                let part = fragment(for: node)
                states[current].epsilon.append(part.start)
                current = part.accept
            }
            let accept = addState()
            if let maximum {
                appendOptional(node, count: maximum - minimum, from: current, to: accept)
            } else {
                appendStar(node, from: current, to: accept)
            }
            return (start, accept)
        }

        private mutating func appendOptional(_ node: Node, count: Int, from: Int, to accept: Int) {
            var current = from
            for _ in 0 ..< max(0, count) {
                let part = fragment(for: node)
                states[current].epsilon.append(part.start)
                states[current].epsilon.append(accept)
                current = part.accept
            }
            states[current].epsilon.append(accept)
        }

        private mutating func appendStar(_ node: Node, from current: Int, to accept: Int) {
            let part = fragment(for: node)
            states[current].epsilon.append(part.start)
            states[current].epsilon.append(accept)
            states[part.accept].epsilon.append(part.start)
            states[part.accept].epsilon.append(accept)
        }
    }
}

public extension PureXML.Regex {
    /// A compiled regular expression in the XML Schema flavor: literals, `.`, the
    /// character-class escapes (`\d \D \w \W \s \S \i \I \c \C`), single-character
    /// escapes, character classes with ranges and negation, grouping, alternation
    /// (`|`), and the quantifiers `?`, `*`, `+`, `{n}`, `{n,}`, `{n,m}`. Matching
    /// is whole-string (anchored), as XSD `pattern` facets require. Built on a
    /// Thompson NFA, so it runs in time linear in the input with no backtracking
    /// blow-up. Unicode category escapes (`\p{...}`) are not yet supported.
    struct Pattern: Sendable {
        private let nfa: NFA

        /// Compiles a pattern.
        public init(_ pattern: String) throws {
            nfa = try NFABuilder.build(RegexParser.parse(pattern))
        }

        /// Whether `string` matches the pattern in full.
        public func matches(_ string: String) -> Bool {
            nfa.matchesWhole(string)
        }
    }

    /// Compiles and matches in one step.
    static func matches(_ pattern: String, _ string: String) throws -> Bool {
        try Pattern(pattern).matches(string)
    }
}
