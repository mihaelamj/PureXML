public extension PureXML.Model {
    /// A single name/value attribute on an XML element.
    struct Attribute: Equatable, Hashable, Sendable {
        public var name: QualifiedName
        public var value: String

        public init(name: QualifiedName, value: String) {
            self.name = name
            self.value = value
        }

        public init(_ name: String, _ value: String) {
            self.name = QualifiedName(name)
            self.value = value
        }
    }
}
