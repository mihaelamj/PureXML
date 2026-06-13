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
        public let abstractTypes: Set<String>
        public let typeBlock: [String: Set<PureXML.Schema.DerivationMethod>]
        public let elementBlock: [String: Set<PureXML.Schema.DerivationMethod>]
        public let typeDerivation: [String: PureXML.Schema.TypeDerivation]

        public init(
            types: [String: PureXML.Schema.ElementType],
            constraints: [String: [PureXML.Schema.IdentityConstraint]],
            rootDeclaration: PureXML.Schema.ElementType?,
            nillableElements: Set<String> = [],
            elementConstraints: [String: PureXML.Schema.ValueConstraint] = [:],
            abstractTypes: Set<String> = [],
            typeBlock: [String: Set<PureXML.Schema.DerivationMethod>] = [:],
            elementBlock: [String: Set<PureXML.Schema.DerivationMethod>] = [:],
            typeDerivation: [String: PureXML.Schema.TypeDerivation] = [:],
        ) {
            self.types = types
            self.constraints = constraints
            self.rootDeclaration = rootDeclaration
            self.nillableElements = nillableElements
            self.elementConstraints = elementConstraints
            self.abstractTypes = abstractTypes
            self.typeBlock = typeBlock
            self.elementBlock = elementBlock
            self.typeDerivation = typeDerivation
        }
    }

    /// XSD validation expressed as composable ``Validation`` values over an
    /// ``XSDContext``, in the OpenAPIKit idiom: each rule is a named, removable
    /// ``Validation`` value with a positive description, and the ``validator()``
    /// composes them; failures are located ``ValidationError``s.
    ///
    /// Scope note (the #101 decision). XSD content validation is *one* recursive
    /// ``Validation`` (``contentValidity``) rather than a separate rule per
    /// constraint, because XSD is a recursive type system: a child's type is
    /// resolved from its parent's content model and position, then rewritten by
    /// `xsi:type` and the derivation controls mid-walk. The constraint categories
    /// (attributes, content model, derivation, nillability, fixed values) are
    /// interdependent through that resolution, so they cannot be split into
    /// independent rules without either changing semantics or duplicating the
    /// recursion. This is the sanctioned multi-error form (the rule's `check`
    /// returns one located error per violation). Each category is isolation-tested
    /// through crafted inputs so it is verifiable on its own, which is the
    /// testability the idiom asks for. Identity constraints, which *are*
    /// independent, are a separate rule (``identityConstraints``).
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
                        abstractTypes: context.document.abstractTypes,
                        typeBlock: context.document.typeBlock,
                        elementBlock: context.document.elementBlock,
                        typeDerivation: context.document.typeDerivation,
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
                    guard case let .element(root) = context.subject else { return [] }
                    return PureXML.Schema.IdentityValidator(constraints: context.document.constraints)
                        .validate(PureXML.Model.TreeNode(context.subject), at: [.element(root.name.description)])
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
