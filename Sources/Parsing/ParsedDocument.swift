public extension PureXML.Parsing {
    /// A parsed document together with the metadata gathered alongside its tree:
    /// the parsed DTD (entities, content models, notations, and so on) and the XML
    /// declaration, when the document opens with one.
    struct ParsedDocument: Sendable {
        public var node: PureXML.Model.Node
        public var documentType: DocumentType
        public var declaration: XMLDeclaration?

        public init(node: PureXML.Model.Node, documentType: DocumentType, declaration: XMLDeclaration? = nil) {
            self.node = node
            self.documentType = documentType
            self.declaration = declaration
        }
    }
}
