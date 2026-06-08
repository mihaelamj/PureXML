public extension PureXML.Validation {
    /// Rule-based assertion validation (the libxml2 `schematron.h` model).
    ///
    /// A Schematron schema groups `<rule>`s into `<pattern>`s. Each rule has a
    /// `context` XPath selecting the nodes it fires on, and `<assert>`/`<report>`
    /// children whose `test` XPath is evaluated relative to each context node. An
    /// `assert` whose test is false, and a `report` whose test is true, produce an
    /// ``Issue`` carrying the element's message.
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

        /// Validates an XML document against the schema, returning one issue per
        /// failed assertion and per matched report, in document order.
        public func validate(_ xml: String) throws -> [Issue] {
            let root = try PureXML.parseTree(xml)
            var issues: [Issue] = []
            for pattern in patterns {
                evaluate(pattern, over: root, into: &issues)
            }
            return issues
        }

        private func evaluate(_ pattern: SchematronPattern, over root: PureXML.Model.TreeNode, into issues: inout [Issue]) {
            var claimed: Set<ObjectIdentifier> = []
            for rule in pattern.rules {
                for node in rule.context.nodes(over: root) where claimed.insert(ObjectIdentifier(node)).inserted {
                    apply(rule.assertions, at: node, into: &issues)
                }
            }
        }

        private func apply(_ assertions: [SchematronAssertion], at node: PureXML.Model.TreeNode, into issues: inout [Issue]) {
            for assertion in assertions {
                let holds = (try? assertion.test.value(at: node).boolean) ?? false
                if assertion.isReport {
                    if holds { issues.append(Issue(severity: .warning, message: assertion.message)) }
                } else if !holds {
                    issues.append(Issue(severity: .error, message: assertion.message))
                }
            }
        }
    }
}
