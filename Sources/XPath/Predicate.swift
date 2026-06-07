extension PureXML.XPath {
    /// A step predicate (`[...]`). A supported, practical subset: a position, an
    /// attribute existence or equality test, or a child-element existence or
    /// equality test.
    enum Predicate: Equatable {
        /// A one-based position, as in `book[1]`.
        case position(Int)
        /// `[@id]`: the context element has the named attribute.
        case hasAttribute(String)
        /// `[@id='x']`: the named attribute equals the value.
        case attributeEquals(name: String, value: String)
        /// `[title]`: the context element has a child element with the name.
        case hasChild(String)
        /// `[title='x']`: a child element with the name has the string value.
        case childEquals(name: String, value: String)
    }
}
