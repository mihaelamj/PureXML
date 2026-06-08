public extension PureXML.Validation {
    /// An atomic validation: a positive `description` of the correct state, a
    /// `validate` function returning one ``ValidationError`` per problem, and a
    /// `predicate` that scopes when the rule applies. Validations are composable
    /// values, combined with the operator algebra, never imperative if-trees.
    ///
    /// Specialized on `Subject` (the value type it fires on, anywhere in the tree)
    /// and parameterized over `Document` (the cross-cutting context, or `Void`
    /// when a rule needs nothing beyond its subject).
    struct Validation<Subject: Validatable, Document> {
        public let validate: (ValidationContext<Subject, Document>) -> [ValidationError]
        public let predicate: (ValidationContext<Subject, Document>) -> Bool
        public let description: String

        /// Runs the validation against `subject`, gating on the predicate first.
        public func apply(to subject: Subject, at codingPath: [PathKey], in document: Document) -> [ValidationError] {
            let context = ValidationContext(document: document, subject: subject, codingPath: codingPath)
            guard predicate(context) else { return [] }
            return validate(context)
        }

        /// The multi-error form: return one error per problem. Use when a single
        /// value can fail in several places at once.
        public init(
            description: String? = nil,
            check validate: @escaping (ValidationContext<Subject, Document>) -> [ValidationError],
            when predicate: @escaping (ValidationContext<Subject, Document>) -> Bool = { _ in true },
        ) {
            self.validate = validate
            self.predicate = predicate
            self.description = description ?? String(describing: Subject.self)
        }

        /// The single-error Bool form (the dominant one): a positive `description`
        /// and a check returning `false` when invalid, which auto-produces the
        /// error `"Failed to satisfy: <description>"`.
        public init(
            description: String,
            check validate: @escaping (ValidationContext<Subject, Document>) -> Bool,
            when predicate: @escaping (ValidationContext<Subject, Document>) -> Bool = { _ in true },
        ) {
            self.init(
                description: description,
                check: { context in
                    validate(context) ? [] : [ValidationError(reason: "Failed to satisfy: \(description)", at: context.codingPath)]
                },
                when: predicate,
            )
        }
    }
}

extension PureXML.Validation {
    /// Erases the subject type of a ``Validation`` so a heterogeneous list can be
    /// applied at every node. Filters by runtime type, guarding against an
    /// optional satisfying a non-optional validation.
    struct AnyValidation<Document> {
        let description: String
        private let applyErased: (Any, [PathKey], Document) -> [ValidationError]

        init<Subject>(_ validation: Validation<Subject, Document>) {
            description = validation.description
            applyErased = { input, codingPath, document in
                guard let subject = input as? Subject, type(of: subject) == type(of: input) else { return [] }
                return validation.apply(to: subject, at: codingPath, in: document)
            }
        }

        func apply(to value: Any, at codingPath: [PathKey], in document: Document) -> [ValidationError] {
            applyErased(value, codingPath, document)
        }
    }
}
