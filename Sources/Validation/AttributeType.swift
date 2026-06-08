extension PureXML.Validation {
    /// The declared type of a DTD attribute. Remaining tokenized types (NMTOKEN,
    /// ENTITY, and so on) are treated as unconstrained character data; only an
    /// enumeration constrains the value, and the ID family drives cross-document
    /// uniqueness and reference checks.
    enum AttributeType: Equatable {
        case cdata
        case enumeration([String])
        /// `ID`: the value must be unique across the document.
        case id
        /// `IDREF`: the value must match some declared `ID`.
        case idReference
        /// `IDREFS`: each whitespace-separated value must match some declared `ID`.
        case idReferences
    }
}
