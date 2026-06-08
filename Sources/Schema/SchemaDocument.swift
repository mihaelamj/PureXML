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
        private let nillableElements: Set<String>
        private let elementConstraints: [String: ValueConstraint]

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
            nillableElements = compiled.nillableElements
            elementConstraints = compiled.elementConstraints
        }

        /// Validates an instance document against the schema, returning one located
        /// ``PureXML/Validation/ValidationError`` per violation. Reports an error
        /// when the root element has no global declaration.
        public func validate(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
            try validate(PureXML.parse(xml))
        }

        /// Validates an already-parsed node tree, so a caller can validate the same
        /// (possibly recovered) tree it is editing. See ``validate(_:)-(String)``.
        public func validate(_ node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
            guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
                return [.init(reason: "the document has no root element", at: [])]
            }
            guard let declaration = elements[root.name.localName] else {
                return [.init(reason: "no element declaration for '\(root.name.localName)'", at: [])]
            }
            let context = PureXML.Validation.XSDContext(
                types: types,
                constraints: constraints,
                rootDeclaration: declaration,
                nillableElements: nillableElements,
                elementConstraints: elementConstraints,
            )
            return PureXML.Validation.XSD.validator().errors(for: .element(root), in: context)
        }

        /// What the schema allows at the element a coding `path` addresses in
        /// `tree`: the next child elements (the content-model follow-set), whether
        /// the content may end there, and the declared attributes with their
        /// required/present status. For editor completions and "what's missing".
        /// Returns nil when the path does not address a declared element.
        public func completions(at path: [PureXML.Validation.PathKey], in tree: PureXML.Model.TreeNode) -> Completions? {
            guard let node = tree.node(at: path), case let .element(element) = node.node,
                  let type = CompletionEngine.elementType(at: path, elements: elements, types: types)
            else {
                return nil
            }
            return CompletionEngine.completions(for: element, type: type, types: types)
        }

        /// The quick-fixes the schema offers at the element a coding `path`
        /// addresses in `tree`: add a required-but-absent attribute, or insert a
        /// still-expected required child. Derived from the structured
        /// ``completions(at:in:)``, with precise placement from the node's content
        /// span, so the edits are exact, not guessed from a message.
        public func quickFixes(at path: [PureXML.Validation.PathKey], in tree: PureXML.Model.TreeNode) -> [PureXML.QuickFix] {
            guard let completions = completions(at: path, in: tree), let element = tree.node(at: path) else { return [] }
            return PureXML.QuickFixEngine.fixes(from: completions, element: element)
        }
    }
}
