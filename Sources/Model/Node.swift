public extension PureXML.Model {
    /// A node in an XML tree. The model preserves document order and the
    /// distinction between text, CDATA, comments, and processing instructions
    /// so that emitting can round-trip a parsed document.
    indirect enum Node: Equatable, Hashable, Sendable {
        /// The root of a parsed document, holding its prolog and root element.
        case document([Node])
        /// An element with a name, attributes, and children.
        case element(Element)
        /// Character data between markup.
        case text(String)
        /// A `<![CDATA[ ... ]]>` section. Stored as its raw inner text.
        case cdata(String)
        /// A `<!-- ... -->` comment. Stored as its raw inner text.
        case comment(String)
        /// A `<?target data?>` processing instruction.
        case processingInstruction(target: String, data: String)

        /// The wrapped ``Element`` when this node is an element.
        public var element: Element? {
            guard case let .element(element) = self else { return nil }
            return element
        }
    }
}
