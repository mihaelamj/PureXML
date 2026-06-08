public extension PureXML.Parsing {
    /// An unparsed general entity: declared with an external identifier and an
    /// `NDATA` notation (`<!ENTITY name SYSTEM "..." NDATA gif>`). Its content is
    /// never parsed as XML; a processor hands it to the application by notation.
    struct UnparsedEntity: Equatable, Sendable {
        /// The entity's external identifier (its `SYSTEM`/`PUBLIC` location).
        public var id: ExternalID
        /// The name of the notation declared for the entity's data.
        public var notation: String

        public init(id: ExternalID, notation: String) {
            self.id = id
            self.notation = notation
        }
    }
}
