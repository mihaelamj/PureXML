public extension PureXML.Schema {
    /// One named complex type's compile-time derivation facts: the subject of
    /// the schema-consistency rules.
    struct SchemaTypeFact: PureXML.Validation.Validatable {
        public let name: String
        public let derivation: TypeDerivation?

        public init(name: String, derivation: TypeDerivation?) {
            self.name = name
            self.derivation = derivation
        }
    }

    /// The compiled context the schema-consistency rules read: the named-type
    /// table and each type's `final` controls.
    struct CompiledSchemaFacts {
        public let types: [String: ElementType]
        public let typeDerivation: [String: TypeDerivation]
        public let typeFinal: [String: Set<DerivationMethod>]

        public init(types: [String: ElementType], typeDerivation: [String: TypeDerivation], typeFinal: [String: Set<DerivationMethod>]) {
            self.types = types
            self.typeDerivation = typeDerivation
            self.typeFinal = typeFinal
        }
    }
}

public extension PureXML.Validation {
    /// Schema-consistency validation, expressed in the validation framework:
    /// each named type is a ``PureXML/Schema/SchemaTypeFact`` subject checked by
    /// composable rules, so a schema with several problems reports them all at
    /// once instead of failing on the first.
    enum XSDSchema {
        /// A type derives from its base only by methods the base permits.
        static var finalRespected: Validation<PureXML.Schema.SchemaTypeFact, PureXML.Schema.CompiledSchemaFacts> {
            .init(description: "A type derives from its base only by methods the base permits") { context in
                guard let derivation = context.subject.derivation,
                      context.document.typeFinal[derivation.base]?.contains(derivation.method) == true
                else { return [] }
                let method = methodName(derivation.method)
                let reason = "type '\(context.subject.name)' derives from '\(derivation.base)' by \(method), which '\(derivation.base)' declares final"
                return [ValidationError(reason: reason, at: context.codingPath)]
            }
        }

        /// A complex type derived by restriction accepts a subset of its base
        /// ("Particle Valid (Restriction)", XSD 1.0).
        static var restrictionsAreSubsets: Validation<PureXML.Schema.SchemaTypeFact, PureXML.Schema.CompiledSchemaFacts> {
            .init(description: "A restriction's content model accepts a subset of its base's") { context in
                guard let derivation = context.subject.derivation, derivation.method == .restriction,
                      case let .complex(restricted)? = context.document.types[context.subject.name],
                      case let .complex(base)? = context.document.types[derivation.base],
                      let reason = PureXML.Schema.ParticleRestriction.violation(
                          restricted: restricted.content,
                          base: base.content,
                          types: context.document.types,
                          derivation: context.document.typeDerivation,
                      )
                else { return [] }
                let text = "type '\(context.subject.name)' is not a valid restriction of '\(derivation.base)': \(reason)"
                return [ValidationError(reason: text, at: context.codingPath)]
            }
        }

        /// Every consistency finding across the schema's named types, each
        /// located at its type, in deterministic order.
        static func consistencyErrors(
            types: [String: PureXML.Schema.ElementType],
            typeDerivation: [String: PureXML.Schema.TypeDerivation],
            typeFinal: [String: Set<PureXML.Schema.DerivationMethod>],
        ) -> [ValidationError] {
            let facts = PureXML.Schema.CompiledSchemaFacts(types: types, typeDerivation: typeDerivation, typeFinal: typeFinal)
            let rules = [finalRespected, restrictionsAreSubsets]
            return typeDerivation.keys.sorted().flatMap { name -> [ValidationError] in
                let fact = PureXML.Schema.SchemaTypeFact(name: name, derivation: typeDerivation[name])
                return rules.flatMap { $0.apply(to: fact, at: [.element(name)], in: facts) }
            }
        }

        private static func methodName(_ method: PureXML.Schema.DerivationMethod) -> String {
            switch method {
            case .extension: "extension"
            case .restriction: "restriction"
            case .substitution: "substitution"
            }
        }
    }
}
