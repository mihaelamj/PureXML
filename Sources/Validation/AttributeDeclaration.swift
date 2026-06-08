extension PureXML.Validation {
    /// One declared attribute from a DTD `<!ATTLIST>`: its name, type, and
    /// default declaration.
    struct AttributeDeclaration: Equatable {
        let name: String
        let type: AttributeType
        let defaultDecl: AttributeDefault
    }
}
