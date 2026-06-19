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

        /// The union of two wildcard constraints (XSD 1.0 `cos-aw-union`), used when
        /// a complexContent extension adds its own `anyAttribute`.
        func union(with other: Wildcard) -> Wildcard {
            Wildcard(
                namespace: Self.unionNamespace(namespace, other.namespace),
                processContents: Self.unionProcessContents(processContents, other.processContents),
                targetNamespace: targetNamespace ?? other.targetNamespace,
            )
        }

        /// Combines optional wildcards from a base type and a derivation.
        static func union(_ left: Wildcard?, _ right: Wildcard?) -> Wildcard? {
            switch (left, right) {
            case (nil, nil): nil
            case (let left?, nil): left
            case (nil, let right?): right
            case let (left?, right?): left.union(with: right)
            }
        }

        private static func unionNamespace(_ left: WildcardNamespace, _ right: WildcardNamespace) -> WildcardNamespace {
            switch (left, right) {
            case (.any, _), (_, .any): .any
            case (.other, .other): .other
            case let (.enumerated(lhs), .enumerated(rhs)): .enumerated(lhs.union(rhs))
            case (.other, _), (_, .other): .any
            }
        }

        private static func unionProcessContents(_ left: ProcessContents, _ right: ProcessContents) -> ProcessContents {
            if left == .strict || right == .strict { return .strict }
            if left == .lax || right == .lax { return .lax }
            return .skip
        }

        /// The intersection of two wildcard constraints (XSD 1.0 `cos-aw-intersect`),
        /// used to combine the `anyAttribute` wildcards a complex type or attribute
        /// group draws from its own declaration and its referenced attribute groups:
        /// the effective wildcard admits only what every source admits.
        func intersection(with other: Wildcard) -> Wildcard {
            Wildcard(
                namespace: Self.intersectNamespace(self, other),
                processContents: Self.intersectProcessContents(processContents, other.processContents),
                targetNamespace: targetNamespace ?? other.targetNamespace,
            )
        }

        /// Combines optional wildcards from several sources by intersection. A nil
        /// source contributes no constraint (the unconstrained `##any` identity), so
        /// a single wildcard is returned unchanged: only a type drawing on two or
        /// more `anyAttribute`s narrows.
        static func intersection(_ left: Wildcard?, _ right: Wildcard?) -> Wildcard? {
            switch (left, right) {
            case (nil, nil): nil
            case (let left?, nil): left
            case (nil, let right?): right
            case let (left?, right?): left.intersection(with: right)
            }
        }

        private static func intersectNamespace(_ left: Wildcard, _ right: Wildcard) -> WildcardNamespace {
            switch (left.namespace, right.namespace) {
            case (.any, _): right.namespace
            case (_, .any): left.namespace
            case let (.enumerated(lhs), .enumerated(rhs)): .enumerated(lhs.intersection(rhs))
            case let (.enumerated(uris), .other): .enumerated(Self.exclude(uris, otherThan: right.targetNamespace))
            case let (.other, .enumerated(uris)): .enumerated(Self.exclude(uris, otherThan: left.targetNamespace))
            case (.other, .other):
                // Two `##other`s with the same target namespace intersect to the
                // same `##other`; with different targets the true intersection
                // (neither target, nor absent) is not expressible in XSD 1.0, so
                // keep the less restrictive `##other` rather than over-reject.
                .other
            }
        }

        /// The URIs of `uris` that `##other` (relative to `targetNamespace`) also
        /// admits: a non-empty namespace other than the target. The empty string
        /// (absent / `##local`) and the target namespace are dropped.
        private static func exclude(_ uris: Set<String>, otherThan targetNamespace: String?) -> Set<String> {
            uris.filter { !$0.isEmpty && $0 != (targetNamespace ?? "") }
        }

        private static func intersectProcessContents(_ left: ProcessContents, _ right: ProcessContents) -> ProcessContents {
            // When the two differ the intersection is strictly not expressible; keep
            // the less strict so a matched attribute is never validated more harshly
            // than either source asked for (under-validation, not over-rejection).
            if left == right { return left }
            if left == .skip || right == .skip { return .skip }
            return .lax
        }
    }

    /// The term of a particle: an element declaration, a nested model group, or a
    /// wildcard.
    indirect enum Term: Sendable {
        /// `typeName` is the resolved local name of the element's `type` reference
        /// (a built-in, a user type, or `anyType` for an absent type), or nil when
        /// the type is an inline anonymous definition. It preserves the derivation
        /// identity the flattened `type` (`ElementType`) loses, for NameAndTypeOK.
        /// `block` is the element's `{disallowed substitutions}` (its own `block`, or
        /// the schema's `blockDefault`), needed for the NameAndTypeOK block-superset
        /// rule in Particle Valid (Restriction); empty when nothing is blocked.
        case element(
            name: PureXML.Model.QualifiedName,
            type: ElementType?,
            typeName: String?,
            valueConstraint: ValueConstraint? = nil,
            block: Set<DerivationMethod> = [],
            nillable: Bool = false,
        )
        case group(Group)
        case wildcard(Wildcard)
    }

    /// A particle: a term with an occurrence range. `maxOccurs` nil means
    /// unbounded.
    struct Particle: Sendable {
        public var occurrenceRange: OccurrenceRange
        public var term: Term

        public var minOccurs: Int {
            get { occurrenceRange.minimum.clamped(to: Int.max) }
            set { occurrenceRange.minimum = NonNegativeDecimal(newValue) }
        }

        public var maxOccurs: Int? {
            get { occurrenceRange.maximum.clamped(to: Int.max) }
            set { occurrenceRange.maximum = OccurrenceUpper(newValue) }
        }

        public init(minOccurs: Int = 1, maxOccurs: Int? = 1, term: Term) {
            occurrenceRange = OccurrenceRange(minimum: minOccurs, maximum: maxOccurs)
            self.term = term
        }

        public init(occurrenceRange: OccurrenceRange, term: Term) {
            self.occurrenceRange = occurrenceRange
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

        /// The constraint's value, whether `default` or `fixed`: the value an
        /// empty element or absent attribute takes.
        public var value: String {
            switch self {
            case let .default(value), let .fixed(value): value
            }
        }
    }

    /// An attribute use on a complex type.
    struct AttributeUse: Sendable {
        public var name: PureXML.Model.QualifiedName
        public var type: SimpleType
        public var required: Bool
        public var valueConstraint: ValueConstraint?
        /// When true, an unprefixed instance attribute may match this use if the
        /// element is in the same namespace (chameleon include only).
        public var chameleonUnprefixed: Bool
        /// `use="prohibited"`: the attribute is excluded from the type's effective
        /// {attribute uses}, so it must not appear on an instance. The use is kept
        /// (rather than dropped) so schema-validity checks still see the declaration.
        public var prohibited: Bool

        public init(
            name: PureXML.Model.QualifiedName,
            type: SimpleType,
            required: Bool = false,
            valueConstraint: ValueConstraint? = nil,
            chameleonUnprefixed: Bool = false,
            prohibited: Bool = false,
        ) {
            self.name = name
            self.type = type
            self.required = required
            self.valueConstraint = valueConstraint
            self.chameleonUnprefixed = chameleonUnprefixed
            self.prohibited = prohibited
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
