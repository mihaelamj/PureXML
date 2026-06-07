public extension PureXML.Model {
    /// An XML element: a qualified name, ordered attributes, and ordered child nodes.
    struct Element: Equatable, Hashable, Sendable {
        public var name: QualifiedName
        public var attributes: [Attribute]
        public var children: [Node]

        public init(
            name: QualifiedName,
            attributes: [Attribute] = [],
            children: [Node] = [],
        ) {
            self.name = name
            self.attributes = attributes
            self.children = children
        }

        public init(
            _ name: String,
            attributes: [Attribute] = [],
            children: [Node] = [],
        ) {
            self.init(
                name: QualifiedName(name),
                attributes: attributes,
                children: children,
            )
        }

        /// The concatenated text of direct text and CDATA children.
        public var text: String {
            children.reduce(into: "") { accumulated, child in
                switch child {
                case let .text(value), let .cdata(value):
                    accumulated += value
                default:
                    break
                }
            }
        }
    }
}
