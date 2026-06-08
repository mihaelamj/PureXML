public extension PureXML.Validation {
    /// A DTD schema: the element content models declared by `<!ELEMENT>` and the
    /// attribute declarations from `<!ATTLIST>`, against which a parsed tree can
    /// be validated. Built from the internal subset surfaced by the parser.
    struct DTDSchema: Sendable {
        let models: [String: ContentModel]
        let attributes: [String: [AttributeDeclaration]]

        init(_ documentType: PureXML.Parsing.DocumentType) {
            var parsedModels: [String: ContentModel] = [:]
            for (name, model) in documentType.elementModels {
                parsedModels[name] = ContentModelParser.parse(model)
            }
            models = parsedModels

            var parsedAttributes: [String: [AttributeDeclaration]] = [:]
            for (name, body) in documentType.attributeLists {
                parsedAttributes[name] = AttributeListParser.parse(body)
            }
            attributes = parsedAttributes
        }

        /// Whether the schema declares any elements or attributes.
        public var isEmpty: Bool {
            models.isEmpty && attributes.isEmpty
        }
    }
}
