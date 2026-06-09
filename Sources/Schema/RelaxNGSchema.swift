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

        /// Whether `xml` is valid against the schema, validated while it is pulled
        /// event by event (the libxml2 `xmlTextReader` model) rather than over a
        /// built tree. The Brzozowski derivative is itself incremental, so only the
        /// residual pattern and a light per-element whitespace frame are retained.
        public func validate(streaming xml: String, limits: PureXML.Parsing.Limits = .default) throws -> Bool {
            let engine = RelaxNGEngine(defines: defines)
            var state = engine.streamingStart(start)
            var reader = PureXML.Parsing.EventReader(xml, limits: limits)
            while let event = try reader.next() {
                engine.streamingConsume(event, into: &state)
            }
            return engine.streamingValid(state)
        }

        /// Every way `xml` fails the schema, as located errors with recovery hints,
        /// so an editor can show all of a faulty document's problems at once rather
        /// than only the first. An empty array means the document is valid.
        public func errors(in xml: String) throws -> [PureXML.Validation.ValidationError] {
            guard case let .document(children) = try PureXML.parse(xml),
                  let root = children.compactMap(\.element).first
            else {
                return [PureXML.Validation.ValidationError(reason: "the document has no root element", at: [])]
            }
            return RelaxNGEngine(defines: defines).locatedErrors(start: start, root: root)
        }

        /// The schema as a single ``PureXML/Validation/Validation`` over the
        /// document root, so RELAX NG composes with the rest of the validation
        /// framework exactly like the XSD, DTD, and Schematron rules.
        public func validation() -> PureXML.Validation.Validation<PureXML.Model.Node, Void> {
            let start = start
            let defines = defines
            return .init(
                description: "Document satisfies the RELAX NG schema",
                check: { context in
                    let root: PureXML.Model.Element? = switch context.subject {
                    case let .document(children): children.compactMap(\.element).first
                    case let .element(element): element
                    default: nil
                    }
                    guard let root else { return [] }
                    return RelaxNGEngine(defines: defines).locatedErrors(start: start, root: root)
                },
                when: { $0.codingPath.isEmpty },
            )
        }
    }
}
