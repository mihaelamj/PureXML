public extension PureXML.Validation {
    /// The schema-independent structural validations: well-formedness rules that
    /// hold for any document regardless of a DTD or schema.
    enum Structural {
        /// An element must not declare the same attribute name twice. Reports one
        /// error per duplicate.
        public static var uniqueAttributes: Validation<PureXML.Model.Element, Void> {
            .init(description: "Element attribute names are unique") { context in
                var seen: Set<String> = []
                var errors: [ValidationError] = []
                for attribute in context.subject.attributes {
                    let key = attribute.name.description
                    if !seen.insert(key).inserted {
                        errors.append(ValidationError(
                            reason: "Duplicate attribute '\(key)' on <\(context.subject.name.description)>",
                            at: context.codingPath,
                        ))
                    }
                }
                return errors
            }
        }

        /// The default structural rule set.
        static var defaults: [Validation<PureXML.Model.Element, Void>] {
            [uniqueAttributes]
        }
    }
}

extension PureXML.Validation.Validator where Document == Void {
    /// Validates a node with the structural rules, throwing a
    /// ``PureXML/Validation/ValidationErrorCollection`` on any failure.
    func validate(_ node: PureXML.Model.Node, strict: Bool = true) throws {
        try validate(node, in: (), strict: strict)
    }

    /// The structural errors for a node, in document order; empty when valid.
    func errors(for node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
        errors(for: node, in: ())
    }

    /// The structural warnings for a node, in document order.
    func warnings(for node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
        warnings(for: node, in: ())
    }

    /// Every structural finding for a node, errors and warnings together.
    func findings(for node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
        findings(for: node, in: ())
    }
}
