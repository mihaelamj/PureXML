public extension PureXML.XPath {
    /// A node selected by an XPath query: either a tree node or an attribute
    /// (attributes are not ``PureXML/Model/Node`` values, so they are surfaced
    /// here alongside nodes).
    enum Selection: Equatable, Sendable {
        case node(PureXML.Model.Node)
        case attribute(PureXML.Model.Attribute)

        /// The selected element, when this selection is an element node.
        public var element: PureXML.Model.Element? {
            guard case let .node(node) = self, case let .element(element) = node else {
                return nil
            }
            return element
        }

        /// The XPath string-value: an attribute's value, or the concatenation of
        /// all descendant character data for a node.
        public var stringValue: String {
            switch self {
            case let .attribute(attribute):
                attribute.value
            case let .node(node):
                Self.stringValue(of: node)
            }
        }

        private static func stringValue(of node: PureXML.Model.Node) -> String {
            switch node {
            case let .text(value), let .cdata(value), let .comment(value):
                value
            case let .processingInstruction(_, data):
                data
            case let .element(element):
                element.children.reduce(into: "") { $0 += stringValue(of: $1) }
            case let .document(children):
                children.reduce(into: "") { $0 += stringValue(of: $1) }
            }
        }
    }
}
