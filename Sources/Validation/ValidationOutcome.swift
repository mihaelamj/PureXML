public extension PureXML.Validation {
    /// The outcome of validating a node: errors, optional warnings, and a validity
    /// flag. Non-throwing recovery accessor beside ``Validator/validate(_:in:strict:)``.
    struct ValidationOutcome: Equatable, Sendable {
        public let errors: [ValidationError]
        public let warnings: [ValidationError]

        /// True when there are no errors and no warnings.
        public var isValid: Bool {
            errors.isEmpty && warnings.isEmpty
        }

        public init(errors: [ValidationError], warnings: [ValidationError] = []) {
            self.errors = errors
            self.warnings = warnings
        }
    }
}

public extension PureXML.Validation.Validator {
    /// Validates `node` in `document`, returning a ``ValidationOutcome`` instead
    /// of throwing. When `strict` is true, warnings are merged into `errors`
    /// (matching the throwing entry point's default).
    func outcome(for node: PureXML.Model.Node, in document: Document, strict: Bool = false) -> PureXML.Validation.ValidationOutcome {
        let split = PureXML.Validation.splitFindings(findings(for: node, in: document))
        if strict {
            return PureXML.Validation.ValidationOutcome(errors: split.errors + split.warnings)
        }
        return PureXML.Validation.ValidationOutcome(errors: split.errors, warnings: split.warnings)
    }

    /// Validates `node` in `document`, returning a ``ValidationOutcome`` instead of throwing.
    func outcome(for node: PureXML.Model.Node, in document: Document) -> PureXML.Validation.ValidationOutcome {
        outcome(for: node, in: document, strict: false)
    }
}
