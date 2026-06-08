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

    /// An element wildcard (`xs:any`). The minimal namespace constraint: any
    /// element matches.
    struct Wildcard: Sendable {
        public init() {}
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

    /// The declared type of an element: a simple type (text only) or a complex one.
    indirect enum ElementType: Sendable {
        case simple(SimpleType)
        case complex(ComplexType)
    }

    /// An attribute use on a complex type.
    struct AttributeUse: Sendable {
        public var name: PureXML.Model.QualifiedName
        public var type: SimpleType
        public var required: Bool

        public init(name: PureXML.Model.QualifiedName, type: SimpleType, required: Bool = false) {
            self.name = name
            self.type = type
            self.required = required
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

    /// A complex type: its attribute uses, whether unknown attributes are allowed,
    /// and its content model.
    struct ComplexType: Sendable {
        public var attributes: [AttributeUse]
        public var allowsOtherAttributes: Bool
        public var content: ContentType

        public init(
            attributes: [AttributeUse] = [],
            allowsOtherAttributes: Bool = false,
            content: ContentType = .empty,
        ) {
            self.attributes = attributes
            self.allowsOtherAttributes = allowsOtherAttributes
            self.content = content
        }
    }
}
