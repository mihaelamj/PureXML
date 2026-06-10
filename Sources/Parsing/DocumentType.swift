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
        /// The name in `<!DOCTYPE name ...>`: the root element's required type
        /// (VC: Root Element Type).
        public var name: String?
        /// Element types declared by more than one `<!ELEMENT>` (VC: Unique
        /// Element Type Declaration); the first declaration stays in effect.
        public var duplicateElements: Set<String> = []
        /// General entities declared in the internal subset; the rest came from
        /// the external subset (the standalone VCs and WFC depend on origin).
        public var internalEntities: Set<String> = []
        /// Element types whose content model was declared in the internal subset.
        public var internalElementModels: Set<String> = []
        /// The `<!ATTLIST>` bodies declared in the internal subset only, keyed
        /// by element, so externally-declared attributes are distinguishable.
        public var internalAttributeLists: [String: String] = [:]
        /// Validity (not well-formedness) findings discovered while scanning
        /// the DTD: an undeclared entity referenced where the external subset
        /// might have declared it (VC: Entity Declared) or a content-model
        /// group split across parameter entities (VC: Proper Group/PE
        /// Nesting). Reported by the validator at the document root.
        public var validityFindings: [String] = []

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
