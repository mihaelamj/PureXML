public extension PureXML.Validation {
    /// A DTD schema: the element content models declared by `<!ELEMENT>` and the
    /// attribute declarations from `<!ATTLIST>`, against which a parsed tree can
    /// be validated. Built from the internal subset surfaced by the parser.
    struct DTDSchema: Sendable {
        let models: [String: ContentModel]
        let attributes: [String: [AttributeDeclaration]]
        /// The names declared by `<!NOTATION>`, against which a `NOTATION` attribute
        /// value (and the names listed in its declaration) are checked.
        let notations: Set<String>
        /// The names of declared unparsed (`NDATA`) entities, against which an
        /// `ENTITY`/`ENTITIES` attribute value is checked.
        let unparsedEntities: Set<String>
        /// The `<!DOCTYPE name ...>` name the root element must match
        /// (VC: Root Element Type).
        let doctypeName: String?
        /// Validity findings about the declarations themselves (duplicate
        /// element types, repeated mixed-content names, multiple ID attributes,
        /// undeclared notations in NOTATION lists, illegal attribute defaults),
        /// each located at the declaration it is about.
        let declarationErrors: [PureXML.Validation.ValidationError]
        /// Whether the document declared `standalone='yes'`, which forbids
        /// depending on external declarations (2.9).
        let standalone: Bool
        /// Element types whose content model came from the external subset.
        let externalElementModels: Set<String>
        /// Attribute declarations whose winning declaration came from the
        /// external subset, keyed by element.
        let externalAttributes: [String: [AttributeDeclaration]]

        init(_ documentType: PureXML.Parsing.DocumentType, standalone: Bool = false) {
            notations = Set(documentType.notations.keys)
            unparsedEntities = Set(documentType.unparsedEntities.keys)
            doctypeName = documentType.name
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
            let scanned = documentType.validityFindings.map { finding in
                PureXML.Validation.ValidationError(
                    reason: finding.reason,
                    at: finding.subject.map { [PureXML.Validation.PathKey.element($0)] } ?? [],
                )
            }
            declarationErrors = scanned + Self.declarationFindings(documentType, attributes: parsedAttributes, notations: notations)
            self.standalone = standalone
            externalElementModels = Set(documentType.elementModels.keys).subtracting(documentType.internalElementModels)
            var external: [String: [AttributeDeclaration]] = [:]
            for (element, declarations) in parsedAttributes {
                let internalNames = Set(
                    AttributeListParser.parse(documentType.internalAttributeLists[element] ?? "").map(\.name),
                )
                let externallyDeclared = declarations.filter { !internalNames.contains($0.name) }
                if !externallyDeclared.isEmpty {
                    external[element] = externallyDeclared
                }
            }
            externalAttributes = external
        }

        /// Whether the schema declares any elements or attributes.
        public var isEmpty: Bool {
            models.isEmpty && attributes.isEmpty
        }
    }
}
