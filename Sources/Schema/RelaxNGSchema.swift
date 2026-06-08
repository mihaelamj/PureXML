public extension PureXML.Schema {
    /// A compiled RELAX NG schema (XML syntax). `validate(_:)` checks an instance
    /// document by the derivative algorithm.
    struct RelaxNG: Sendable {
        private let start: Pattern
        private let defines: [String: Pattern]

        /// Compiles a RELAX NG schema document.
        public init(_ rng: String) throws {
            (start, defines) = try RelaxNGParser.parse(rng)
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
