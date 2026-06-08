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
    /// selects it. Dynamic message content is evaluated: `<value-of select=>`
    /// renders the string value of its XPath at the context node, and `<name>`
    /// renders the node's name, so a finding can report actual values. A `<phase>`
    /// (or the schema's `defaultPhase`) scopes which patterns run.
    struct Schematron {
        private let schema: SchematronSchema

        /// Compiles a Schematron schema document. Throws if a context or test is
        /// not a valid XPath expression.
        public init(schema xml: String) throws {
            schema = try SchematronParser.parse(xml)
        }

        /// Validates an XML document against the schema, returning one finding per
        /// failed assertion and per matched report, in document order. Assertions
        /// are errors and reports are warnings. With `phase` (or the schema's
        /// `defaultPhase`), only the patterns that phase activates run; nil or
        /// `#ALL` runs every pattern.
        public func validate(_ xml: String, phase: String? = nil) throws -> [ValidationError] {
            let node = try PureXML.parse(xml)
            return Validator<Void>.blank.validating(Self.rule(activePatterns(phase: phase))).errors(for: node, in: ())
        }

        /// The patterns active in the requested phase, falling back to the schema's
        /// declared default phase; all patterns when no phase scopes them.
        private func activePatterns(phase requested: String?) -> [SchematronPattern] {
            let selected = requested ?? schema.defaultPhase
            guard let selected, selected != "#ALL", let active = schema.phases[selected] else {
                return schema.patterns
            }
            let ids = Set(active)
            return schema.patterns.filter { $0.id.map(ids.contains) ?? false }
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
                    errors += apply(rule.assertions, at: node, variables: bindings(rule.lets, at: node))
                }
            }
            return errors
        }

        /// Evaluates a rule's `<let>` bindings at the context node, in order, so a
        /// later binding can reference an earlier one through `$name`.
        private static func bindings(_ lets: [SchematronLet], at node: PureXML.Model.TreeNode) -> [String: PureXML.XPath.Value] {
            var variables: [String: PureXML.XPath.Value] = [:]
            for binding in lets {
                if let value = try? binding.value.value(at: node, variables: variables) {
                    variables[binding.name] = value
                }
            }
            return variables
        }

        private static func apply(
            _ assertions: [SchematronAssertion],
            at node: PureXML.Model.TreeNode,
            variables: [String: PureXML.XPath.Value],
        ) -> [ValidationError] {
            let path = codingPath(of: node)
            var errors: [ValidationError] = []
            for assertion in assertions {
                let holds = (try? assertion.test.value(at: node, variables: variables).boolean) ?? false
                if assertion.isReport {
                    if holds { errors.append(ValidationError(reason: render(assertion.message, at: node, variables: variables), at: path, severity: .warning)) }
                } else if !holds {
                    errors.append(ValidationError(reason: render(assertion.message, at: node, variables: variables), at: path, severity: .error))
                }
            }
            return errors
        }

        /// Renders a message template against the context node: literal text as is,
        /// `<value-of>` as the string value of its XPath, `<name>` as the node's
        /// name. Whitespace runs are collapsed so the rendered message reads
        /// cleanly regardless of source indentation.
        private static func render(
            _ parts: [SchematronMessagePart],
            at node: PureXML.Model.TreeNode,
            variables: [String: PureXML.XPath.Value],
        ) -> String {
            let joined = parts.map { part -> String in
                switch part {
                case let .text(text): text
                case let .valueOf(query): (try? query.value(at: node, variables: variables).string) ?? ""
                case .name: node.name?.description ?? ""
                }
            }.joined()
            return joined.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
