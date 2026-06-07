public extension PureXML.Stream {
    /// One document from a parsed stream, carrying its zero-based stream index
    /// so that validation can report which document an issue belongs to.
    struct Document: Equatable, Hashable, Sendable {
        public var index: Int
        public var node: PureXML.Model.Node

        public init(index: Int, node: PureXML.Model.Node) {
            self.index = index
            self.node = node
        }
    }
}
