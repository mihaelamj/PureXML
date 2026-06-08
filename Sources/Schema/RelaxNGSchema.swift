public extension PureXML.Schema {
    /// A compiled RELAX NG schema (XML syntax). `validate(_:)` checks an instance
    /// document by the derivative algorithm.
    struct RelaxNG: Sendable {
        private let start: Pattern
        private let defines: [String: Pattern]

        /// Compiles a RELAX NG schema document (XML syntax). `schemaLoader`
        /// resolves the `href` of `include` and `externalRef` to schema source;
        /// it returns nil (the default) when external schemas are not available.
        public init(_ rng: String, schemaLoader: @escaping (String) -> String? = { _ in nil }) throws {
            (start, defines) = try RelaxNGParser.parse(rng, loader: schemaLoader)
        }

        /// Compiles a RELAX NG schema in the compact syntax (RNC). `schemaLoader`
        /// resolves `include` and `external` references to compact-syntax source.
        public init(compact rnc: String, schemaLoader: @escaping (String) -> String? = { _ in nil }) throws {
            (start, defines) = try RelaxNGCompactParser.parse(rnc, loader: schemaLoader)
        }

        /// Whether `xml` is valid against the schema.
        public func validate(_ xml: String) throws -> Bool {
            guard case let .document(children) = try PureXML.parse(xml),
                  let root = children.compactMap(\.element).first
            else {
                return false
            }
            return RelaxNGEngine(defines: defines).matches(start: start, root: .element(root))
        }
    }
}
