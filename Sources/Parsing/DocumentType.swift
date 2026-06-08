public extension PureXML.Parsing {
    /// What the parser extracted from a `<!DOCTYPE>`: the internal general
    /// entities, the `<!ELEMENT>` content-model strings, the `<!ATTLIST>` bodies,
    /// the parameter entities, any external entity declarations, and the external
    /// subset identifier. Empty when no DTD was processed.
    struct DocumentType: Equatable, Sendable {
        public var entities: [String: String]
        public var elementModels: [String: String]
        /// Raw `<!ATTLIST>` bodies keyed by element name (the text between the
        /// element name and `>`, concatenated across multiple declarations).
        public var attributeLists: [String: String]
        /// Internal parameter entities (`<!ENTITY % name "value">`) keyed by name,
        /// with their values already parameter-expanded. DTD-only; never visible
        /// in document content.
        public var parameterEntities: [String: String]
        /// External general entity declarations keyed by name. Their replacement
        /// text is loaded only through an injected ``EntityResolver``.
        public var externalEntities: [String: ExternalID]
        /// The external subset identifier from `<!DOCTYPE root SYSTEM/PUBLIC ...>`,
        /// or nil when the DOCTYPE has no external subset.
        public var externalSubset: ExternalID?
        /// `<!NOTATION>` declarations keyed by name, with their external identifier.
        public var notations: [String: ExternalID]
        /// Unparsed general entities (`<!ENTITY name SYSTEM "..." NDATA n>`) keyed by
        /// name. Their content is never parsed; the notation names how to handle it.
        public var unparsedEntities: [String: UnparsedEntity]

        public init(
            entities: [String: String] = [:],
            elementModels: [String: String] = [:],
            attributeLists: [String: String] = [:],
            parameterEntities: [String: String] = [:],
            externalEntities: [String: ExternalID] = [:],
            externalSubset: ExternalID? = nil,
            notations: [String: ExternalID] = [:],
            unparsedEntities: [String: UnparsedEntity] = [:],
        ) {
            self.entities = entities
            self.elementModels = elementModels
            self.attributeLists = attributeLists
            self.parameterEntities = parameterEntities
            self.externalEntities = externalEntities
            self.externalSubset = externalSubset
            self.notations = notations
            self.unparsedEntities = unparsedEntities
        }
    }
}
