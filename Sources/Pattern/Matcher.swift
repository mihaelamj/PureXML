extension PureXML.Pattern {
    /// How a step connects to the step on its left (its parent in the pattern).
    enum Gap: Equatable, Sendable {
        /// The first step must be the document root element.
        case root
        /// The immediate parent (a single `/`).
        case child
        /// Any ancestor (a `//`, or a relative pattern's floating start).
        case descendant
    }

    /// A name test in a pattern step.
    enum NameMatch: Equatable, Sendable {
        case wildcard
        case name(String)
        case prefixWildcard(String)

        func matches(_ name: PureXML.Model.QualifiedName) -> Bool {
            switch self {
            case .wildcard:
                return true
            case let .prefixWildcard(prefix):
                return name.prefix == prefix
            case let .name(text):
                if text.contains(":") { return name.description == text }
                return name.description == text || name.localName == text
            }
        }
    }

    /// One compiled pattern step.
    struct PatternStep: Equatable, Sendable {
        let gap: Gap
        let test: NameMatch
    }
}

public extension PureXML.Pattern {
    /// A compiled streaming pattern (the libxml2 `pattern.h` XPath subset): element
    /// names, `*`, `prefix:*`, `/`, `//`, an absolute leading `/`, and an optional
    /// trailing attribute step. Predicates, `.`/`..`, and the general expression
    /// language are out of the streamable subset and are rejected at compile time.
    ///
    /// A pattern is matched against an element's ancestor-or-self path (root first),
    /// which a streaming reader knows from its open-element stack, so no tree is
    /// needed.
    struct Matcher: Sendable {
        let elementSteps: [PatternStep]
        let attributeTest: NameMatch?

        /// Compiles a pattern string.
        public init(_ pattern: String) throws {
            (elementSteps, attributeTest) = try PatternCompiler.compile(pattern)
        }

        /// Whether this pattern selects attributes rather than elements.
        public var matchesAttributes: Bool {
            attributeTest != nil
        }

        /// Whether the element at the end of `path` (root first) matches an
        /// element pattern. Always false for an attribute pattern.
        public func matchesElement(path: [PureXML.Model.QualifiedName]) -> Bool {
            guard attributeTest == nil, !path.isEmpty else { return false }
            return matchesElementPath(path)
        }

        /// The attributes of the element at the end of `path` that this pattern
        /// selects. Empty for an element pattern.
        public func matchingAttributes(
            path: [PureXML.Model.QualifiedName],
            attributes: [PureXML.Model.Attribute],
        ) -> [PureXML.Model.Attribute] {
            guard let attributeTest, !path.isEmpty, matchesElementPath(path) else { return [] }
            return attributes.filter { attributeTest.matches($0.name) }
        }

        /// Whether the element steps match `path` ending at the last element.
        private func matchesElementPath(_ path: [PureXML.Model.QualifiedName]) -> Bool {
            guard !elementSteps.isEmpty else { return true }
            return matchUpTo(elementSteps.count - 1, path.count - 1, path)
        }

        /// Whether `elementSteps[0...stepIndex]` match the path ending at
        /// `pathIndex`, with `elementSteps[stepIndex]` matching `path[pathIndex]`.
        private func matchUpTo(_ stepIndex: Int, _ pathIndex: Int, _ path: [PureXML.Model.QualifiedName]) -> Bool {
            guard pathIndex >= 0 else { return false }
            let step = elementSteps[stepIndex]
            guard step.test.matches(path[pathIndex]) else { return false }
            if stepIndex == 0 {
                return step.gap == .root ? pathIndex == 0 : true
            }
            switch step.gap {
            case .child:
                return matchUpTo(stepIndex - 1, pathIndex - 1, path)
            case .descendant:
                return ancestorMatches(stepIndex - 1, below: pathIndex, path)
            case .root:
                return false
            }
        }

        /// Whether `elementSteps[0...stepIndex]` match some ancestor strictly above
        /// `pathIndex` (the `//` gap allows any number of intervening ancestors).
        private func ancestorMatches(_ stepIndex: Int, below pathIndex: Int, _ path: [PureXML.Model.QualifiedName]) -> Bool {
            var candidate = pathIndex - 1
            while candidate >= 0 {
                if matchUpTo(stepIndex, candidate, path) { return true }
                candidate -= 1
            }
            return false
        }
    }
}
