public extension PureXML.Validation {
    /// Applies a set of ``Validation`` values across a parsed node tree, gathering
    /// every error with its coding path and throwing one ``ValidationErrorCollection``
    /// at the end. Holds default rules in two tiers (non-reference, then reference)
    /// plus any custom additions, in that order. Build one with ``blank`` and the
    /// fluent ``validating(_:)``/``withoutValidating(_:)`` methods, or take a layer's
    /// default factory.
    ///
    /// Parameterized over `Document`, the cross-cutting context the rules consult
    /// (a schema, a scope, or `Void` for rules that need only their subject).
    final class Validator<Document>: @unchecked Sendable {
        fileprivate let nonReferenceDefaultValidations: [AnyValidation<Document>]
        fileprivate let referenceDefaultValidations: [AnyValidation<Document>]
        fileprivate let customValidations: [AnyValidation<Document>]

        init(
            nonReferenceDefaultValidations: [AnyValidation<Document>],
            referenceDefaultValidations: [AnyValidation<Document>],
            customValidations: [AnyValidation<Document>],
        ) {
            self.nonReferenceDefaultValidations = nonReferenceDefaultValidations
            self.referenceDefaultValidations = referenceDefaultValidations
            self.customValidations = customValidations
        }

        /// A validator with no rules; add your own with ``validating(_:)``.
        public static var blank: Validator {
            Validator(nonReferenceDefaultValidations: [], referenceDefaultValidations: [], customValidations: [])
        }

        /// The descriptions of the active rules, in application order.
        public var validationDescriptions: [String] {
            validations.map(\.description)
        }

        /// Descriptions of the non-reference default tier, in order.
        public var nonReferenceValidationDescriptions: [String] {
            nonReferenceDefaultValidations.map(\.description)
        }

        /// Descriptions of the reference default tier, in order.
        public var referenceValidationDescriptions: [String] {
            referenceDefaultValidations.map(\.description)
        }

        /// Descriptions of the custom tier, in order.
        public var customValidationDescriptions: [String] {
            customValidations.map(\.description)
        }

        fileprivate var validations: [AnyValidation<Document>] {
            nonReferenceDefaultValidations + referenceDefaultValidations + customValidations
        }

        /// Returns a validator with `additions` appended to the custom tier.
        @discardableResult
        public func validating<Subject>(_ additions: Validation<Subject, Document>...) -> Validator {
            Validator(
                nonReferenceDefaultValidations: nonReferenceDefaultValidations,
                referenceDefaultValidations: referenceDefaultValidations,
                customValidations: customValidations + additions.map { AnyValidation($0) },
            )
        }

        /// Returns a validator with one named builtin rule appended to the custom tier.
        @discardableResult
        public func validating(
            _ rule: KeyPath<BuiltinValidation.Type, Validation<some Any, Document>>,
        ) -> Validator {
            validating(BuiltinValidation.self[keyPath: rule])
        }

        /// Returns a validator with several named builtin rules appended (mixed subject types).
        @discardableResult
        public func validating<each Subject: Validatable>(
            _ rules: repeat KeyPath<BuiltinValidation.Type, Validation<each Subject, Document>>,
        ) -> Validator {
            var result = self
            for rule in repeat each rules {
                result = result.validating(BuiltinValidation.self[keyPath: rule])
            }
            return result
        }

        /// Returns a validator with a single-error Bool rule appended to the custom tier.
        @discardableResult
        public func validating<Subject>(
            _ description: String,
            check: @escaping (ValidationContext<Subject, Document>) -> Bool,
            when predicate: @escaping (ValidationContext<Subject, Document>) -> Bool = { _ in true },
        ) -> Validator {
            validating(Validation(description: description, check: check, when: predicate))
        }

        /// Returns a validator with the rules matching `descriptions` removed from
        /// every tier.
        @discardableResult
        public func withoutValidating(_ descriptions: String...) -> Validator {
            let drop = Set(descriptions)
            func filter(_ tier: [AnyValidation<Document>]) -> [AnyValidation<Document>] {
                tier.filter { !drop.contains($0.description) }
            }
            return Validator(
                nonReferenceDefaultValidations: filter(nonReferenceDefaultValidations),
                referenceDefaultValidations: filter(referenceDefaultValidations),
                customValidations: filter(customValidations),
            )
        }

        /// Applies every active rule to `subject` at `path` in `document`, without
        /// walking a node tree. Used for compile-time schema checks and other
        /// single-subject validation passes.
        public func errors(
            for subject: some Validatable,
            at path: [PathKey] = [],
            in document: Document,
        ) -> [ValidationError] {
            var findings: [ValidationError] = []
            apply(subject, at: path, in: document, into: &findings)
            return PureXML.Validation.splitFindings(findings).errors
        }

        // MARK: Running

        /// Every validation finding for `node` in `document`, including advisory
        /// warnings from rules and from ``HasWarnings`` values.
        public func findings(for node: PureXML.Model.Node, in document: Document) -> [ValidationError] {
            var findings: [ValidationError] = []
            walk(node, path: [], document, &findings)
            return findings
        }

        /// Gathers every error-severity finding from validating `node` in `document`.
        public func errors(for node: PureXML.Model.Node, in document: Document) -> [ValidationError] {
            PureXML.Validation.splitFindings(findings(for: node, in: document)).errors
        }

        /// Gathers every warning-severity finding from validating `node` in `document`.
        public func warnings(for node: PureXML.Model.Node, in document: Document) -> [ValidationError] {
            PureXML.Validation.splitFindings(findings(for: node, in: document)).warnings
        }

        /// Validates `node` in `document`, throwing a ``ValidationErrorCollection``
        /// when any error-severity finding occurs, and also when any warning occurs
        /// and `strict` is true (the default).
        public func validate(_ node: PureXML.Model.Node, in document: Document, strict: Bool = true) throws {
            let split = PureXML.Validation.splitFindings(findings(for: node, in: document))
            let toThrow = strict ? split.errors + split.warnings : split.errors
            if !toThrow.isEmpty { throw ValidationErrorCollection(values: toThrow) }
        }

        /// Validates `root` and its subtree in document order. The walk is
        /// iterative, driven by an explicit `(node, path)` stack, so a deeply
        /// nested document does not overflow the call stack; children are pushed
        /// reversed so they pop in document order, giving the same pre-order
        /// finding sequence a recursive descent would.
        private func walk(_ root: PureXML.Model.Node, path rootPath: [PathKey], _ document: Document, _ findings: inout [ValidationError]) {
            var stack: [(node: PureXML.Model.Node, path: [PathKey])] = [(root, rootPath)]
            while let (node, path) = stack.popLast() {
                apply(node, at: path, in: document, into: &findings)
                let children: [PureXML.Model.Node]
                switch node {
                case let .document(documentChildren):
                    children = documentChildren
                case let .element(element):
                    apply(element, at: path, in: document, into: &findings)
                    for attribute in element.attributes {
                        apply(attribute, at: path + [.attribute(attribute.name.localName)], in: document, into: &findings)
                    }
                    children = element.children
                case .text, .cdata, .comment, .processingInstruction:
                    continue
                }
                let elementNames = children.compactMap { child -> String? in
                    guard case let .element(element) = child else { return nil }
                    return element.name.description
                }
                var steps = PathKey.steps(forChildNames: elementNames).makeIterator()
                var childItems: [(node: PureXML.Model.Node, path: [PathKey])] = []
                childItems.reserveCapacity(children.count)
                for child in children {
                    if case .element = child {
                        childItems.append((child, path + [steps.next() ?? .element("")]))
                    } else {
                        childItems.append((child, path))
                    }
                }
                stack.append(contentsOf: childItems.reversed())
            }
        }

        private func apply(_ value: some Validatable, at path: [PathKey], in document: Document, into findings: inout [ValidationError]) {
            for validation in validations {
                findings += validation.apply(to: value, at: path, in: document)
            }
            if let warningSource = value as? HasWarnings {
                findings += warningSource.validationWarnings(at: path)
            }
        }
    }
}

public extension PureXML.Validation.Validator where Document == Void {
    /// The default structural validator: schema-independent well-formedness rules.
    convenience init() {
        self.init(
            nonReferenceDefaultValidations: PureXML.Validation.Structural.defaults.map { PureXML.Validation.AnyValidation($0) },
            referenceDefaultValidations: [],
            customValidations: [],
        )
    }
}

extension PureXML.Validation.Validator {
    /// Builds a validator whose default tiers are populated explicitly.
    static func defaults(
        nonReference: [PureXML.Validation.AnyValidation<Document>] = [],
        reference: [PureXML.Validation.AnyValidation<Document>] = [],
    ) -> PureXML.Validation.Validator<Document> {
        PureXML.Validation.Validator(
            nonReferenceDefaultValidations: nonReference,
            referenceDefaultValidations: reference,
            customValidations: [],
        )
    }
}
