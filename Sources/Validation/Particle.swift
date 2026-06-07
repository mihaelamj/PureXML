extension PureXML.Validation {
    /// A particle of a DTD element-content model: an element name, a sequence
    /// (`,`), or a choice (`|`), each carrying an occurrence indicator. The
    /// content model is effectively a regular expression over child element
    /// names, and a particle is one node of that expression.
    indirect enum Particle: Equatable {
        case name(String, Occurrence)
        case sequence([Particle], Occurrence)
        case choice([Particle], Occurrence)
    }
}
