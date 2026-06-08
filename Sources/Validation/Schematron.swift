public extension PureXML.Validation {
    /// Rule-based assertion validation (the libxml2 `schematron.h` model).
    ///
    /// A Schematron schema groups `<rule>`s into `<pattern>`s. Each rule has a
    /// `context` XPath selecting the nodes it fires on, and `<assert>`/`<report>`
    /// children whose `test` XPath is evaluated relative to each context node. A
    /// failed `assert` produces an error finding; a matched `report` produces a
    /// warning finding. Both are ``ValidationError`` values carrying the message.
    ///
    /// Within a pattern a node is processed by the first rule whose context
    /// selects it. Dynamic message content (`<value-of>`, `<name>`) is rendered as
    /// its static text; the message substitution itself is not evaluated.
    struct Schematron {
        private let patterns: [SchematronPattern]

        /// Compiles a Schematron schema document. Throws if a context or test is
        /// not a valid XPath expression.
        public init(schema xml: String) throws {
            patterns = try SchematronParser.parse(xml)
        }

        /// Validates an XML document against the schema, returning one finding per
        /// failed assertion and per matched report, in document order. Assertions
        /// are errors and reports are warnings.
        public func validate(_ xml: String) throws -> [ValidationError] {
            let node = try PureXML.parse(xml)
            return Validator<Void>.blank.validating(Self.rule(patterns)).errors(for: node, in: ())
        }

        /// The schema as a single ``Validation`` over the document root, so it
        /// composes with the rest of the framework.
        static func rule(_ patterns: [SchematronPattern]) -> Validation<PureXML.Model.Node, Void> {
            .init(
                description: "Document satisfies the Schematron schema",
                check: { context in evaluate(patterns, over: PureXML.Model.TreeNode(context.subject)) },
                when: { $0.codingPath.isEmpty },
            )
        }

        private static func evaluate(_ patterns: [SchematronPattern], over root: PureXML.Model.TreeNode) -> [ValidationError] {
            patterns.flatMap { evaluate($0, over: root) }
        }

        private static func evaluate(_ pattern: SchematronPattern, over root: PureXML.Model.TreeNode) -> [ValidationError] {
            var errors: [ValidationError] = []
            var claimed: Set<ObjectIdentifier> = []
            for rule in pattern.rules {
                for node in rule.context.nodes(over: root) where claimed.insert(ObjectIdentifier(node)).inserted {
                    errors += apply(rule.assertions, at: node)
                }
            }
            return errors
        }

        private static func apply(_ assertions: [SchematronAssertion], at node: PureXML.Model.TreeNode) -> [ValidationError] {
            let path = codingPath(of: node)
            var errors: [ValidationError] = []
            for assertion in assertions {
                let holds = (try? assertion.test.value(at: node).boolean) ?? false
                if assertion.isReport {
                    if holds { errors.append(ValidationError(reason: assertion.message, at: path, severity: .warning)) }
                } else if !holds {
                    errors.append(ValidationError(reason: assertion.message, at: path, severity: .error))
                }
            }
            return errors
        }

        /// The coding path of a context node, built from the element chain to the
        /// root (a sibling index only when a name repeats), so each finding is
        /// located at the node its rule fired on rather than the document root.
        private static func codingPath(of node: PureXML.Model.TreeNode) -> [PathKey] {
            var steps: [PathKey] = []
            var current: PureXML.Model.TreeNode? = node
            while let element = current, element.kind == .element, let name = element.name?.description {
                steps.append(step(for: element, named: name))
                current = element.parent
            }
            return steps.reversed()
        }

        private static func step(for element: PureXML.Model.TreeNode, named name: String) -> PathKey {
            guard let parent = element.parent else { return .element(name) }
            let siblings = parent.children.filter { $0.kind == .element && $0.name?.description == name }
            guard siblings.count > 1, let index = siblings.firstIndex(where: { $0 === element }) else {
                return .element(name)
            }
            return .element(name, index: index + 1)
        }
    }
}
