extension PureXML.Validation {
    /// How many times a content-model particle may occur: the DTD `?`, `*`, `+`
    /// suffixes (or exactly once with no suffix).
    enum Occurrence: Equatable {
        case once
        case optional
        case zeroOrMore
        case oneOrMore
    }
}
