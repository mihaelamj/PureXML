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
            // A comment or processing-instruction node's own string-value is its
            // data (XPath 1.0 5.6, 5.7), but as a descendant of an element it
            // contributes nothing (5.1, 5.5): only text and CDATA do.
            case let .comment(value):
                return value
            case let .processingInstruction(_, data):
                return data
            case let .text(value), let .cdata(value):
                return value
            case .element, .document:
                // Iterative pre-order walk so a deeply-nested node does not
                // overflow the stack; children are pushed reversed to concatenate
                // descendant text in document order.
                var result = ""
                var stack: [PureXML.Model.Node] = [node]
                while let current = stack.popLast() {
                    switch current {
                    case let .text(value), let .cdata(value):
                        result += value
                    case let .element(element):
                        stack.append(contentsOf: element.children.reversed())
                    case let .document(children):
                        stack.append(contentsOf: children.reversed())
                    case .comment, .processingInstruction:
                        break
                    }
                }
                return result
            }
        }
    }
}
