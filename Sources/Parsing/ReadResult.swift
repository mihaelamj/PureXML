public extension PureXML.Parsing {
    /// The outcome of a recovering read: the best-effort node tree and every
    /// located ``Diagnostic`` found along the way. Equatable, so a deterministic
    /// read can be compared whole.
    struct ReadResult: Equatable, Sendable {
        /// The best-effort tree. Always a document node; as complete as recovery
        /// allowed.
        public var node: PureXML.Model.Node
        /// One diagnostic per problem, in source order. Empty when the input was
        /// well-formed.
        public var diagnostics: [Diagnostic]

        public init(node: PureXML.Model.Node, diagnostics: [Diagnostic]) {
            self.node = node
            self.diagnostics = diagnostics
        }
    }
}
