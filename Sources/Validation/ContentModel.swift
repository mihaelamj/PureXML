extension PureXML.Validation {
    /// A DTD element content model, as declared by `<!ELEMENT name ...>`.
    enum ContentModel: Equatable {
        /// `EMPTY`: the element must have no content.
        case empty
        /// `ANY`: any content is allowed.
        case any
        /// `(#PCDATA)`: character data only, no child elements.
        case pcdata
        /// `(#PCDATA | a | b)*`: text mixed with zero or more of the named elements.
        case mixed([String])
        /// Element content: a particle the child element sequence must match.
        case children(Particle)
    }
}
