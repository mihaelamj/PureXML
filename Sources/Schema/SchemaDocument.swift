public extension PureXML.Schema {
    /// An error compiling or applying a schema.
    enum SchemaError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case notASchema

        public var description: String {
            switch self {
            case .notASchema: "the document is not an xs:schema"
            }
        }
    }

    /// A compiled XSD schema: its global element declarations and named-type
    /// table, parsed from a schema document, used to validate instance documents.
    struct Document: Sendable {
        private let elements: [String: ElementType]
        private let types: [String: ElementType]

        /// Compiles a schema document.
        public init(_ xsd: String) throws {
            (elements, types) = try XSDParser.parse(xsd)
        }

        /// Validates an instance document against the schema, returning one issue
        /// per violation. Reports an issue when the root element has no global
        /// declaration.
        public func validate(_ xml: String) throws -> [PureXML.Validation.Issue] {
            guard case let .document(children) = try PureXML.parse(xml),
                  let root = children.compactMap(\.element).first
            else {
                return [.init(severity: .error, message: "the document has no root element")]
            }
            guard let declaration = elements[root.name.localName] else {
                return [.init(severity: .error, message: "no element declaration for '\(root.name.localName)'")]
            }
            return ComplexValidator(types: types).validate(root, as: declaration)
        }
    }
}
