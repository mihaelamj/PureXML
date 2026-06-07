extension PureXML.XPath {
    /// The node test of a location step: which nodes on the axis qualify.
    enum NodeTest: Equatable {
        /// A local-name match (`book`).
        case name(String)
        /// The `*` wildcard (any element, or any attribute on the attribute axis).
        case wildcard
        /// `text()`: character-data and CDATA nodes.
        case text
        /// `node()`: any node.
        case node
        /// `comment()`: comment nodes.
        case comment
    }
}
