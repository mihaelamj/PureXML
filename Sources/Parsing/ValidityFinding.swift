public extension PureXML.Parsing {
    /// One validity (not well-formedness) discovery made while parsing: a
    /// reason and, when known, the declared name it is about, which becomes
    /// the error's coding path when the validation framework reports it.
    struct ValidityFinding: Equatable, Sendable {
        public var reason: String
        /// The element or declaration name the finding addresses, or nil when
        /// it belongs to the document as a whole.
        public var subject: String?

        public init(_ reason: String, subject: String? = nil) {
            self.reason = reason
            self.subject = subject
        }
    }
}
