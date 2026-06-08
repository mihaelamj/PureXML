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
        private let constraints: [String: [IdentityConstraint]]

        /// Compiles a schema document. `schemaLoader` resolves the
        /// `schemaLocation` of `xs:include`, `xs:import`, and `xs:redefine` to
        /// schema source; it returns nil (the default) when external schemas are
        /// not available, which keeps compilation from reaching the filesystem or
        /// network by default.
        public init(_ xsd: String, schemaLoader: @escaping (String) -> String? = { _ in nil }) throws {
            let compiled = try XSDParser.parse(xsd, loader: schemaLoader)
            elements = compiled.elements
            types = compiled.types
            constraints = compiled.constraints
        }

        /// Validates an instance document against the schema, returning one located
        /// ``PureXML/Validation/ValidationError`` per violation. Reports an error
        /// when the root element has no global declaration.
        public func validate(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
            guard case let .document(children) = try PureXML.parse(xml),
                  let root = children.compactMap(\.element).first
            else {
                return [.init(reason: "the document has no root element", at: [])]
            }
            guard let declaration = elements[root.name.localName] else {
                return [.init(reason: "no element declaration for '\(root.name.localName)'", at: [])]
            }
            let context = PureXML.Validation.XSDContext(types: types, constraints: constraints, rootDeclaration: declaration)
            return PureXML.Validation.XSD.validator().errors(for: .element(root), in: context)
        }
    }
}
