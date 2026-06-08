extension PureXML.XPath {
    /// The node test of a location step: which nodes on the axis qualify.
    enum NodeTest: Equatable {
        /// A name match (`book`), tested against the axis's principal node kind.
        case name(String)
        /// The `*` wildcard (any node of the axis's principal kind).
        case wildcard
        /// `text()`: character-data and CDATA nodes.
        case text
        /// `node()`: any node.
        case node
        /// `comment()`: comment nodes.
        case comment
        /// `processing-instruction()`: PI nodes, optionally with a target literal.
        case processingInstruction(target: String?)
    }
}
