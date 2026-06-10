public extension PureXML.Validation {
    /// Applies a set of ``Validation`` values across a parsed node tree, gathering
    /// every error with its coding path and throwing one ``ValidationErrorCollection``
    /// at the end. Holds an ordered list of erased validations (a layer's default
    /// set plus any custom additions). Build one with ``blank`` and the fluent
    /// ``validating(_:)``/``withoutValidating(_:)`` methods, or take a layer's
    /// default factory.
    ///
    /// Parameterized over `Document`, the cross-cutting context the rules consult
    /// (a schema, a scope, or `Void` for rules that need only their subject).
    struct Validator<Document> {
        var validations: [AnyValidation<Document>]

        init(validations: [AnyValidation<Document>]) {
            self.validations = validations
        }

        /// A validator with no rules; add your own with ``validating(_:)``.
        public static var blank: Validator {
            Validator(validations: [])
        }

        /// The descriptions of the active rules, in application order.
        public var validationDescriptions: [String] {
            validations.map(\.description)
        }

        /// Returns a validator with `additions` appended after the current rules.
        public func validating<Subject>(_ additions: Validation<Subject, Document>...) -> Validator {
            Validator(validations: validations + additions.map { AnyValidation($0) })
        }

        /// Returns a validator with a single-error Bool rule appended.
        public func validating<Subject>(
            _ description: String,
            check: @escaping (ValidationContext<Subject, Document>) -> Bool,
            when predicate: @escaping (ValidationContext<Subject, Document>) -> Bool = { _ in true },
        ) -> Validator {
            validating(Validation(description: description, check: check, when: predicate))
        }

        /// Returns a validator with the rules matching `descriptions` removed.
        public func withoutValidating(_ descriptions: String...) -> Validator {
            Validator(validations: validations.filter { !descriptions.contains($0.description) })
        }

        // MARK: Running

        /// Gathers every error from validating `node` in `document`, in document
        /// order. Returns an empty array when the tree is valid.
        public func errors(for node: PureXML.Model.Node, in document: Document) -> [ValidationError] {
            var errors: [ValidationError] = []
            walk(node, path: [], document, &errors)
            return errors
        }

        /// Validates `node` in `document`, throwing a ``ValidationErrorCollection``
        /// if any rule fails.
        public func validate(_ node: PureXML.Model.Node, in document: Document) throws {
            let found = errors(for: node, in: document)
            if !found.isEmpty { throw ValidationErrorCollection(values: found) }
        }

        private func walk(_ node: PureXML.Model.Node, path: [PathKey], _ document: Document, _ errors: inout [ValidationError]) {
            apply(node, at: path, in: document, into: &errors)
            switch node {
            case let .document(children):
                walkChildren(children, path: path, document, &errors)
            case let .element(element):
                apply(element, at: path, in: document, into: &errors)
                for attribute in element.attributes {
                    apply(attribute, at: path + [.attribute(attribute.name.localName)], in: document, into: &errors)
                }
                walkChildren(element.children, path: path, document, &errors)
            case .text, .cdata, .comment, .processingInstruction:
                break
            }
        }

        /// Recurses element children, extending the path by `name` (and a sibling
        /// index only when more than one child shares that name).
        private func walkChildren(
            _ children: [PureXML.Model.Node],
            path: [PathKey],
            _ document: Document,
            _ errors: inout [ValidationError],
        ) {
            let elementNames = children.compactMap { child -> String? in
                guard case let .element(element) = child else { return nil }
                return element.name.description
            }
            var steps = PathKey.steps(forChildNames: elementNames).makeIterator()
            for child in children {
                guard case .element = child else {
                    walk(child, path: path, document, &errors)
                    continue
                }
                let step = steps.next() ?? .element("")
                walk(child, path: path + [step], document, &errors)
            }
        }

        private func apply(_ value: some Validatable, at path: [PathKey], in document: Document, into errors: inout [ValidationError]) {
            for validation in validations {
                errors += validation.apply(to: value, at: path, in: document)
            }
        }
    }
}
