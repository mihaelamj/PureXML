extension PureXML.Schema.ComplexValidator {
    /// The document-scoped ID uniqueness and IDREF resolution errors gathered
    /// during validation. Call after validating the document root.
    func idErrors() -> [PureXML.Validation.ValidationError] {
        idTracker.errors()
    }

    /// Records a value for document-scoped ID/IDREF checking when its type is
    /// xs:ID, xs:IDREF, or xs:IDREFS. Values are whitespace-collapsed (these types
    /// are NCName-based); an IDREFS value contributes one reference per list item.
    func recordIDs(_ type: PureXML.Schema.SimpleType, value: String, at path: [PureXML.Validation.PathKey]) {
        let normalized = PureXML.Schema.SimpleType.process(value, whiteSpace: .collapse)
        if type.isID {
            idTracker.recordID(normalized, at: path)
        } else if type.isIDReference {
            idTracker.recordReference(normalized, at: path)
        } else if type.isIDReferenceList {
            for token in normalized.split(separator: " ") {
                idTracker.recordReference(String(token), at: path)
            }
        }
    }
}
