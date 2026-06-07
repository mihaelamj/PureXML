public extension PureXML.Parsing {
    /// The pure-Swift XML parser.
    ///
    /// The tokenizing scanner and the well-formedness rules are still being
    /// built out. The public entry points exist and are stable; calling them
    /// today raises ``ParseError/notImplemented(_:)`` so that downstream code
    /// can wire against the final surface before the parser lands.
    struct Parser: Sendable {
        public init() {}

        /// Parses a single XML document into a ``PureXML/Model/Node/document(_:)`` tree.
        public func parse(_ xml: String) throws -> PureXML.Model.Node {
            guard !xml.isEmpty else { throw ParseError.emptyDocument }
            throw ParseError.notImplemented("document parsing")
        }
    }
}
