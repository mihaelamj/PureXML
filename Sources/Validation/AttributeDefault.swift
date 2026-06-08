extension PureXML.Validation {
    /// The default declaration of a DTD attribute (`#REQUIRED`, `#IMPLIED`,
    /// `#FIXED "value"`, or a literal default value).
    enum AttributeDefault: Equatable {
        case required
        case implied
        case fixed(String)
        case value(String)
    }
}
