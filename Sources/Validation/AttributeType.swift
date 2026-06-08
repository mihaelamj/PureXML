extension PureXML.Validation {
    /// The declared type of a DTD attribute. An enumeration constrains the value to
    /// a fixed set; the tokenized types constrain its lexical form (a name token, a
    /// name); and the ID family drives cross-document uniqueness and reference
    /// checks.
    enum AttributeType: Equatable {
        case cdata
        case enumeration([String])
        /// `NOTATION (a|b)`: the value must be one of the listed notation names,
        /// each of which must be a declared `<!NOTATION>`.
        case notation([String])
        /// `ID`: the value must be unique across the document.
        case id
        /// `IDREF`: the value must match some declared `ID`.
        case idReference
        /// `IDREFS`: each whitespace-separated value must match some declared `ID`.
        case idReferences
        /// `NMTOKEN`: the value must be a single XML name token.
        case nmToken
        /// `NMTOKENS`: each whitespace-separated value must be a name token.
        case nmTokens
        /// `ENTITY`: the value must be an XML name (naming an unparsed entity).
        case entity
        /// `ENTITIES`: each whitespace-separated value must be a name.
        case entities
    }
}
