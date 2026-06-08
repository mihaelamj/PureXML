public extension PureXML.Validation {
    /// The compiled-schema context the XSD validations read: the named-type table
    /// a content model resolves against, the identity constraints, and the root
    /// element's declared type.
    struct XSDContext {
        public let types: [String: PureXML.Schema.ElementType]
        public let constraints: [String: [PureXML.Schema.IdentityConstraint]]
        public let rootDeclaration: PureXML.Schema.ElementType?
        public let nillableElements: Set<String>
        public let elementConstraints: [String: PureXML.Schema.ValueConstraint]

        public init(
            types: [String: PureXML.Schema.ElementType],
            constraints: [String: [PureXML.Schema.IdentityConstraint]],
            rootDeclaration: PureXML.Schema.ElementType?,
            nillableElements: Set<String> = [],
            elementConstraints: [String: PureXML.Schema.ValueConstraint] = [:],
        ) {
            self.types = types
            self.constraints = constraints
            self.rootDeclaration = rootDeclaration
            self.nillableElements = nillableElements
            self.elementConstraints = elementConstraints
        }
    }

    /// XSD validation expressed as composable ``Validation`` values over an
    /// ``XSDContext``. The content-model check is inherently recursive (a child's
    /// type depends on its position), so each rule delegates to the recursive
    /// validators while contributing located ``ValidationError`` results to one
    /// collection.
    enum XSD {
        /// The document element is valid against its declared XSD type.
        static var contentValidity: Validation<PureXML.Model.Node, XSDContext> {
            .init(
                description: "The document element is valid against its XSD type",
                check: { context in
                    guard case let .element(root) = context.subject, let declaration = context.document.rootDeclaration else {
                        return []
                    }
                    return PureXML.Schema.ComplexValidator(
                        types: context.document.types,
                        nillableElements: context.document.nillableElements,
                        elementConstraints: context.document.elementConstraints,
                    )
                    .validate(root, as: declaration, at: [.element(root.name.description)])
                },
                when: { $0.codingPath.isEmpty },
            )
        }

        /// The document's XSD identity constraints (`unique`, `key`, `keyref`) hold.
        static var identityConstraints: Validation<PureXML.Model.Node, XSDContext> {
            .init(
                description: "XSD identity constraints hold",
                check: { context in
                    PureXML.Schema.IdentityValidator(constraints: context.document.constraints)
                        .validate(PureXML.Model.TreeNode(context.subject))
                },
                when: { $0.codingPath.isEmpty },
            )
        }

        /// A validator combining the content-model and identity-constraint rules.
        static func validator() -> Validator<XSDContext> {
            Validator<XSDContext>.blank.validating(contentValidity, identityConstraints)
        }
    }
}
