public extension PureXML.Validation {
    /// One conformance-corpus case: a named expectation that some subsystem's
    /// `actual` output equals the authoritative `expected` output. It conforms to
    /// ``Validatable`` so a corpus is checked by a ``Validation`` rule, the same
    /// composable idiom used to validate documents, rather than an ad-hoc loop.
    struct ConformanceCase: Validatable, Equatable, Sendable {
        public let name: String
        public let actual: String
        public let expected: String

        public init(name: String, actual: String, expected: String) {
            self.name = name
            self.actual = actual
            self.expected = expected
        }
    }

    /// Conformance checking, expressed in the validation framework. A corpus is a
    /// set of ``ConformanceCase`` values; the rule states the correct outcome
    /// (positive description) and emits one located ``ValidationError`` per case
    /// whose output diverges, so a suite reports every failure at once.
    enum Conformance {
        /// Each conformance case produces its expected output.
        public static var matchesExpected: Validation<ConformanceCase, Void> {
            .init(description: "Each conformance case produces its expected output") { context in
                let testCase = context.subject
                guard testCase.actual != testCase.expected else { return [] }
                return [
                    ValidationError(
                        reason: "case '\(testCase.name)': produced \"\(testCase.actual)\", expected \"\(testCase.expected)\"",
                        at: [.element(testCase.name)],
                    ),
                ]
            }
        }

        /// A blank validator carrying the conformance rule, so a caller can compose
        /// further checks onto a corpus the same way other subsystems do.
        public static func validator() -> Validator<Void> {
            Validator<Void>.blank.validating(matchesExpected)
        }

        /// Every located failure across a corpus (empty means the whole corpus
        /// conforms). Each case is offered to the conformance rules; failures carry
        /// the case name as their coding path.
        public static func failures(in cases: [ConformanceCase]) -> [ValidationError] {
            cases.flatMap { matchesExpected.apply(to: $0, at: [.element($0.name)], in: ()) }
        }
    }
}
