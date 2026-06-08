extension PureXML.Validation {
    /// The declared type of a DTD attribute. Tokenized types (ID, IDREF, NMTOKEN,
    /// and so on) are treated as unconstrained character data here, since their
    /// value rules are not yet enforced; only an enumeration constrains the value.
    enum AttributeType: Equatable {
        case cdata
        case enumeration([String])
    }
}
