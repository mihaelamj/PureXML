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
            let validation = Self.rule(activePatterns(phase: phase), schemaLets: schema.lets, diagnostics: schema.diagnostics)
            return Validator<Void>.blank.validating(validation).errors(for: node, in: ())
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
        static func rule(
            _ patterns: [SchematronPattern],
            schemaLets: [SchematronLet],
            diagnostics: [String: [SchematronMessagePart]],
        ) -> Validation<PureXML.Model.Node, Void> {
            .init(
                description: "Document satisfies the Schematron schema",
                check: { context in
                    let root = PureXML.Model.TreeNode(context.subject)
                    let base = bindings(schemaLets, at: root, base: [:])
                    return evaluate(patterns, over: root, base: base, diagnostics: diagnostics)
                },
                when: { $0.codingPath.isEmpty },
            )
        }

        private static func evaluate(
            _ patterns: [SchematronPattern],
            over root: PureXML.Model.TreeNode,
            base: [String: PureXML.XPath.Value],
            diagnostics: [String: [SchematronMessagePart]],
        ) -> [ValidationError] {
            patterns.flatMap { evaluate($0, over: root, base: base, diagnostics: diagnostics) }
        }

        private static func evaluate(
            _ pattern: SchematronPattern,
            over root: PureXML.Model.TreeNode,
            base: [String: PureXML.XPath.Value],
            diagnostics: [String: [SchematronMessagePart]],
        ) -> [ValidationError] {
            // Pattern-level lets extend the schema-level base, evaluated at the root.
            let patternBase = bindings(pattern.lets, at: root, base: base)
            var errors: [ValidationError] = []
            var claimed: Set<ObjectIdentifier> = []
            for rule in pattern.rules {
                for node in rule.context.nodes(over: root) where claimed.insert(ObjectIdentifier(node)).inserted {
                    let variables = bindings(rule.lets, at: node, base: patternBase)
                    errors += apply(rule.assertions, at: node, variables: variables, diagnostics: diagnostics)
                }
            }
            return errors
        }

        /// Evaluates `<let>` bindings over `base` at `node`, in order, so a later
        /// binding can reference an earlier one (or a wider-scope one) through
        /// `$name`.
        private static func bindings(_ lets: [SchematronLet], at node: PureXML.Model.TreeNode, base: [String: PureXML.XPath.Value]) -> [String: PureXML.XPath.Value] {
            var variables = base
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
            diagnostics: [String: [SchematronMessagePart]],
        ) -> [ValidationError] {
            let path = codingPath(of: node)
            var errors: [ValidationError] = []
            for assertion in assertions {
                let holds = (try? assertion.test.value(at: node, variables: variables).boolean) ?? false
                let flagged = assertion.isReport ? holds : !holds
                guard flagged else { continue }
                let reason = reason(assertion, at: node, variables: variables, diagnostics: diagnostics)
                errors.append(ValidationError(reason: reason, at: path, severity: assertion.isReport ? .warning : .error))
            }
            return errors
        }

        /// The finding text: the assertion's rendered message, followed by the
        /// rendered text of each `<diagnostic>` it references, for extra detail.
        private static func reason(
            _ assertion: SchematronAssertion,
            at node: PureXML.Model.TreeNode,
            variables: [String: PureXML.XPath.Value],
            diagnostics: [String: [SchematronMessagePart]],
        ) -> String {
            var text = render(assertion.message, at: node, variables: variables)
            for id in assertion.diagnostics {
                guard let parts = diagnostics[id] else { continue }
                let rendered = render(parts, at: node, variables: variables)
                if !rendered.isEmpty { text += " " + rendered }
            }
            return text
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
