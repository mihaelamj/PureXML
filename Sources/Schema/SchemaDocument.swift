public extension PureXML.Schema {
    /// An error compiling or applying a schema.
    enum SchemaError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case notASchema
        /// A type inside `xs:redefine` does not redefine itself: its restriction or
        /// extension base must name the type it redefines.
        case redefineIncompatible(type: String)
        /// An `xs:all` group violates its XSD 1.0 constraints: every member must be
        /// an element with `maxOccurs` at most 1, and the group itself may occur at
        /// most once.
        case invalidAllGroup(reason: String)
        /// A RELAX NG schema document does not match the RELAX NG grammar or
        /// its restrictions (sections 3, 4.16-4.18).
        case invalidRelaxNG(reason: String)
        /// The compiled schema fails one or more consistency rules (a `final`
        /// violation, an unfaithful restriction); every finding is carried, so a
        /// schema with several problems reports them all at once.
        case inconsistent([PureXML.Validation.ValidationError])

        public var description: String {
            switch self {
            case .notASchema:
                "the document is not an xs:schema"
            case let .redefineIncompatible(type):
                "redefined type '\(type)' must derive from itself"
            case let .invalidAllGroup(reason):
                "invalid xs:all group: \(reason)"
            case let .invalidRelaxNG(reason):
                "invalid RELAX NG schema: \(reason)"
            case let .inconsistent(findings):
                findings.map(\.description).joined(separator: "; ")
            }
        }

        /// Every compile-time finding when the schema is inconsistent.
        public var inconsistentFindings: [PureXML.Validation.ValidationError]? {
            if case let .inconsistent(findings) = self { return findings }
            return nil
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
        private let abstractTypes: Set<String>
        private let abstractElements: Set<String>
        private let typeBlock: [String: Set<DerivationMethod>]
        private let elementBlock: [String: Set<DerivationMethod>]
        private let typeDerivation: [String: TypeDerivation]
        private let targetNamespace: String?

        /// Combines already-compiled declaration tables, for merging the schemas
        /// an instance references through `xsi:schemaLocation`. No consistency
        /// check runs: each component schema was validated when first compiled.
        private init(
            elements: [String: ElementType],
            types: [String: ElementType],
            constraints: [String: [IdentityConstraint]],
            nillableElements: Set<String>,
            elementConstraints: [String: ValueConstraint],
            abstractTypes: Set<String>,
            abstractElements: Set<String>,
            typeBlock: [String: Set<DerivationMethod>],
            elementBlock: [String: Set<DerivationMethod>],
            typeDerivation: [String: TypeDerivation],
            targetNamespace: String?,
        ) {
            self.elements = elements
            self.types = types
            self.constraints = constraints
            self.nillableElements = nillableElements
            self.elementConstraints = elementConstraints
            self.abstractTypes = abstractTypes
            self.abstractElements = abstractElements
            self.typeBlock = typeBlock
            self.elementBlock = elementBlock
            self.typeDerivation = typeDerivation
            self.targetNamespace = targetNamespace
        }

        /// This schema with `other`'s global declarations merged in; this schema's
        /// own declarations win on any key conflict. Used to fold in the schemas an
        /// instance points at, so a strict/lax wildcard can resolve elements
        /// declared in another document.
        private func merging(_ other: Document) -> Document {
            func mineFirst<V>(_ mine: [String: V], _ theirs: [String: V]) -> [String: V] {
                mine.merging(theirs) { current, _ in current }
            }
            return Document(
                elements: mineFirst(elements, other.elements),
                types: mineFirst(types, other.types),
                constraints: mineFirst(constraints, other.constraints),
                nillableElements: nillableElements.union(other.nillableElements),
                elementConstraints: mineFirst(elementConstraints, other.elementConstraints),
                abstractTypes: abstractTypes.union(other.abstractTypes),
                abstractElements: abstractElements.union(other.abstractElements),
                typeBlock: mineFirst(typeBlock, other.typeBlock),
                elementBlock: mineFirst(elementBlock, other.elementBlock),
                typeDerivation: mineFirst(typeDerivation, other.typeDerivation),
                targetNamespace: targetNamespace,
            )
        }

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
            abstractTypes = compiled.abstractTypes
            abstractElements = compiled.abstractElements
            typeBlock = compiled.typeBlock
            elementBlock = compiled.elementBlock
            typeDerivation = compiled.typeDerivation
            targetNamespace = compiled.targetNamespace
            // Schema consistency through the validation framework: every named
            // type is checked by the composable rules (final respected, Particle
            // Valid (Restriction)), and ALL findings are reported together, joined
            // with the schema-validity findings gathered while parsing (malformed
            // facet definitions and the like).
            let consistencyFindings = PureXML.Validation.XSDSchema.consistencyErrors(
                types: compiled.types,
                typeDerivation: compiled.typeDerivation,
                typeFinal: compiled.typeFinal,
            )
            let allFindings = compiled.schemaErrors + consistencyFindings
            if !allFindings.isEmpty {
                throw SchemaError.inconsistent(allFindings)
            }
        }

        /// Validates an instance document against the schema, returning one located
        /// ``PureXML/Validation/ValidationError`` per violation. Reports an error
        /// when the root element has no global declaration.
        public func validate(_ xml: String) throws -> [PureXML.Validation.ValidationError] {
            try validate(PureXML.parse(xml))
        }

        /// Validates `xml`, additionally honoring the instance's
        /// `xsi:schemaLocation` and `xsi:noNamespaceSchemaLocation` hints: each
        /// referenced schema document is loaded through `schemaLoader`, compiled,
        /// and its global declarations merged in (this schema's own declarations
        /// win), so a strict or lax wildcard can resolve elements declared in
        /// another document. With no hints this is `validate(_:)`.
        public func validate(_ xml: String, schemaLoader: @escaping (String) -> String?) throws -> [PureXML.Validation.ValidationError] {
            let node = try PureXML.parse(xml)
            return merged(with: node, schemaLoader: schemaLoader).validate(node)
        }

        /// Merges global declarations from every schema document the instance
        /// references through `xsi:schemaLocation` or
        /// `xsi:noNamespaceSchemaLocation`.
        private func merged(with node: PureXML.Model.Node, schemaLoader: @escaping (String) -> String?) -> Document {
            var combined = self
            for location in Self.hintedSchemaLocations(in: node) {
                guard let source = schemaLoader(location),
                      let other = try? Document(source, schemaLoader: schemaLoader)
                else { continue }
                combined = combined.merging(other)
            }
            return combined
        }

        /// The schema-document locations an instance points at through
        /// `xsi:schemaLocation` (the second token of each namespace/location pair)
        /// and `xsi:noNamespaceSchemaLocation` (a single location).
        private static func hintedSchemaLocations(in node: PureXML.Model.Node) -> [String] {
            guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
                return []
            }
            var locations: [String] = []
            for attribute in root.attributes {
                let isInstance = attribute.name.namespaceURI == "http://www.w3.org/2001/XMLSchema-instance"
                    || attribute.name.prefix == "xsi"
                guard isInstance else { continue }
                switch attribute.name.localName {
                case "schemaLocation":
                    let tokens = attribute.value.split(whereSeparator: \.isWhitespace).map(String.init)
                    var index = 1
                    while index < tokens.count {
                        locations.append(tokens[index])
                        index += 2
                    }
                case "noNamespaceSchemaLocation":
                    locations.append(attribute.value)
                default:
                    break
                }
            }
            return locations
        }

        /// Validates `xml` against the schema while it is pulled event by event (the
        /// libxml2 `xmlTextReader` model) rather than over a built tree. Memory is
        /// bounded to the open-element stack. Content models, attributes, and simple
        /// content are checked incrementally; document-scoped identity constraints
        /// are checked once at the end from a parsed tree (the instance is parsed
        /// again only when constraints are present).
        public func validate(streaming xml: String, limits: PureXML.Parsing.Limits = .default) throws -> [PureXML.Validation.ValidationError] {
            let identityNode = constraints.isEmpty ? nil : try PureXML.parse(xml)
            return try validateStreaming(xml, limits: limits, identityNode: identityNode)
        }

        /// Validates `xml` while it is pulled event by event, additionally honoring
        /// the instance's `xsi:schemaLocation` and
        /// `xsi:noNamespaceSchemaLocation` hints through `schemaLoader`. See
        /// ``validate(_:schemaLoader:)-(String)``.
        public func validate(
            streaming xml: String,
            schemaLoader: @escaping (String) -> String?,
            limits: PureXML.Parsing.Limits = .default,
        ) throws -> [PureXML.Validation.ValidationError] {
            let node = try PureXML.parse(xml)
            return try merged(with: node, schemaLoader: schemaLoader).validateStreaming(xml, limits: limits, identityNode: node)
        }

        private func validateStreaming(
            _ xml: String,
            limits: PureXML.Parsing.Limits,
            identityNode: PureXML.Model.Node?,
        ) throws -> [PureXML.Validation.ValidationError] {
            let validator = PureXML.Schema.ComplexValidator(
                types: types,
                nillableElements: nillableElements,
                elementConstraints: elementConstraints,
                abstractTypes: abstractTypes,
                typeBlock: typeBlock,
                elementBlock: elementBlock,
                typeDerivation: typeDerivation,
            )
            var driver = PureXML.Validation.StreamingXSDValidator(
                validator: validator,
                rootElements: elements,
                abstractElements: abstractElements,
                targetNamespace: targetNamespace,
            )
            var reader = PureXML.Parsing.EventReader(xml, limits: limits)
            while let event = try reader.next() {
                driver.consume(event)
            }
            var errors = driver.finish()
            errors += validator.idErrors()
            if !constraints.isEmpty, let identityNode {
                errors += identityErrors(in: identityNode)
            }
            return errors
        }

        /// Identity-constraint findings for an already-parsed instance tree.
        private func identityErrors(in node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
            guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
                return []
            }
            return PureXML.Schema.IdentityValidator(constraints: constraints)
                .validate(PureXML.Model.TreeNode(.element(root)), at: [.element(root.name.description)])
        }

        /// Validates an already-parsed node tree, so a caller can validate the same
        /// (possibly recovered) tree it is editing. See ``validate(_:)-(String)``.
        public func validate(_ node: PureXML.Model.Node) -> [PureXML.Validation.ValidationError] {
            guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
                return [.init(reason: "the document has no root element", at: [])]
            }
            guard let declaration = elements[root.name.localName] else {
                return [.init(reason: "no element declaration for '\(root.name.localName)'", at: [.element(root.name.description)])]
            }
            // A schema with a target namespace declares its global elements in that
            // namespace; the root must be in it.
            if let target = targetNamespace, !target.isEmpty, root.name.namespaceURI != target {
                return [.init(reason: "root element '\(root.name.localName)' is not in the schema target namespace '\(target)'", at: [.element(root.name.description)])]
            }
            // An abstract element may not appear in an instance directly; only a
            // concrete substitution-group member may stand in its place.
            if abstractElements.contains(root.name.localName) {
                return [.init(reason: "abstract element '\(root.name.localName)' must not appear in an instance", at: [.element(root.name.description)])]
            }
            let context = PureXML.Validation.XSDContext(
                types: types,
                constraints: constraints,
                rootDeclaration: declaration,
                nillableElements: nillableElements,
                elementConstraints: elementConstraints,
                abstractTypes: abstractTypes,
                typeBlock: typeBlock,
                elementBlock: elementBlock,
                typeDerivation: typeDerivation,
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
