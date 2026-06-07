public extension PureXML.Parsing {
    /// What the parser extracted from a `<!DOCTYPE>` internal subset: the
    /// internal general entities and the `<!ELEMENT>` content-model strings.
    /// Empty when no DTD was processed.
    struct DocumentType: Equatable, Sendable {
        public var entities: [String: String]
        public var elementModels: [String: String]

        public init(entities: [String: String] = [:], elementModels: [String: String] = [:]) {
            self.entities = entities
            self.elementModels = elementModels
        }
    }
}
