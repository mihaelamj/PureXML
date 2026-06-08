public extension PureXML.Schema {
    /// A model-group compositor.
    enum Compositor: Sendable {
        /// An ordered list (`xs:sequence`).
        case sequence
        /// One of the alternatives (`xs:choice`).
        case choice
        /// Each member once, in any order (`xs:all`).
        case all
    }

    /// The namespace constraint of a wildcard (`xs:any`/`xs:anyAttribute`).
    enum WildcardNamespace: Sendable, Equatable {
        /// `##any`: a name in any namespace, or none.
        case any
        /// `##other`: a name in any namespace other than the target, and not in no
        /// namespace.
        case other
        /// A specific set of namespace URIs; the empty string stands for no
        /// namespace (`##local`).
        case enumerated(Set<String>)
    }

    /// How a wildcard-matched item is validated: `skip` (no validation), `lax`
    /// (validate if a declaration is found), or `strict` (a declaration is
    /// required).
    enum ProcessContents: Sendable, Equatable {
        case skip
        case lax
        case strict
    }

    /// An element or attribute wildcard (`xs:any`/`xs:anyAttribute`): which
    /// namespaces it admits, and how matched items are validated.
    struct Wildcard: Sendable, Equatable {
        public var namespace: WildcardNamespace
        public var processContents: ProcessContents
        /// The schema's target namespace, needed to resolve `##other`.
        public var targetNamespace: String?

        public init(
            namespace: WildcardNamespace = .any,
            processContents: ProcessContents = .strict,
            targetNamespace: String? = nil,
        ) {
            self.namespace = namespace
            self.processContents = processContents
            self.targetNamespace = targetNamespace
        }

        /// Whether `name` is admitted by this wildcard's namespace constraint.
        public func admits(_ name: PureXML.Model.QualifiedName) -> Bool {
            let namespaceURI = name.namespaceURI ?? ""
            switch namespace {
            case .any:
                return true
            case .other:
                return !namespaceURI.isEmpty && namespaceURI != (targetNamespace ?? "")
            case let .enumerated(uris):
                return uris.contains(namespaceURI)
            }
        }
    }

    /// The term of a particle: an element declaration, a nested model group, or a
    /// wildcard.
    indirect enum Term: Sendable {
        case element(name: PureXML.Model.QualifiedName, type: ElementType?)
        case group(Group)
        case wildcard(Wildcard)
    }

    /// A particle: a term with an occurrence range. `maxOccurs` nil means
    /// unbounded.
    struct Particle: Sendable {
        public var minOccurs: Int
        public var maxOccurs: Int?
        public var term: Term

        public init(minOccurs: Int = 1, maxOccurs: Int? = 1, term: Term) {
            self.minOccurs = minOccurs
            self.maxOccurs = maxOccurs
            self.term = term
        }
    }

    /// A model group: a compositor over particles.
    struct Group: Sendable {
        public var compositor: Compositor
        public var particles: [Particle]

        public init(compositor: Compositor, particles: [Particle]) {
            self.compositor = compositor
            self.particles = particles
        }
    }

    /// The declared type of an element: a simple type (text only), a complex one,
    /// or a named reference resolved against the schema's type table (which lets
    /// recursive schemas be represented without an infinite value).
    indirect enum ElementType: Sendable {
        case simple(SimpleType)
        case complex(ComplexType)
        case typeReference(String)
    }

    /// A value constraint on an attribute or element: a default value supplied
    /// when the item is absent, or a fixed value the item must equal.
    enum ValueConstraint: Sendable, Equatable {
        case `default`(String)
        case fixed(String)

        /// The fixed value, when this is a `fixed` constraint.
        public var fixedValue: String? {
            if case let .fixed(value) = self { return value }
            return nil
        }
    }

    /// An attribute use on a complex type.
    struct AttributeUse: Sendable {
        public var name: PureXML.Model.QualifiedName
        public var type: SimpleType
        public var required: Bool
        public var valueConstraint: ValueConstraint?

        public init(
            name: PureXML.Model.QualifiedName,
            type: SimpleType,
            required: Bool = false,
            valueConstraint: ValueConstraint? = nil,
        ) {
            self.name = name
            self.type = type
            self.required = required
            self.valueConstraint = valueConstraint
        }
    }

    /// The content of a complex type.
    indirect enum ContentType: Sendable {
        /// No child elements or non-whitespace text.
        case empty
        /// Character data validated against a simple type, no child elements.
        case simpleContent(SimpleType)
        /// Child elements matching the particle; no non-whitespace text.
        case elementOnly(Particle)
        /// Child elements matching the particle, with text allowed between them.
        case mixed(Particle)
    }

    /// A complex type: its attribute uses, an optional attribute wildcard
    /// (`xs:anyAttribute`) admitting further attributes, and its content model.
    struct ComplexType: Sendable {
        public var attributes: [AttributeUse]
        public var attributeWildcard: Wildcard?
        public var content: ContentType

        public init(
            attributes: [AttributeUse] = [],
            attributeWildcard: Wildcard? = nil,
            content: ContentType = .empty,
        ) {
            self.attributes = attributes
            self.attributeWildcard = attributeWildcard
            self.content = content
        }
    }
}
