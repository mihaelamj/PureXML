/// The lets and assertions of an abstract Schematron rule, named by id so an
/// `<extends>` can pull them into a concrete rule. File-scope and private.
private struct AbstractRule {
    let lets: [PureXML.Validation.SchematronLet]
    let assertions: [PureXML.Validation.SchematronAssertion]
}

extension PureXML.Validation {
    /// Parses a Schematron schema document into patterns and phases. Namespace
    /// agnostic: it matches the `schema`, `phase`, `active`, `pattern`, `rule`,
    /// `assert`, and `report` elements by local name, so both the ISO and the
    /// legacy Schematron namespaces work.
    enum SchematronParser {
        static func parse(_ xml: String) throws -> SchematronSchema {
            let root = try PureXML.parseTree(xml)
            let schema = descendants(root, localName: "schema").first ?? root
            let patterns = try descendants(root, localName: "pattern").map(pattern)
            return try SchematronSchema(
                patterns: patterns,
                phases: phases(root),
                defaultPhase: attribute(schema, "defaultPhase"),
                lets: ruleLets(schema),
                diagnostics: diagnostics(root),
            )
        }

        private static func phases(_ root: PureXML.Model.TreeNode) -> [String: [String]] {
            var result: [String: [String]] = [:]
            for phase in descendants(root, localName: "phase") {
                guard let id = attribute(phase, "id") else { continue }
                result[id] = children(phase, localName: "active").compactMap { attribute($0, "pattern") }
            }
            return result
        }

        private static func pattern(_ node: PureXML.Model.TreeNode) throws -> SchematronPattern {
            let ruleNodes = children(node, localName: "rule")
            var abstracts: [String: AbstractRule] = [:]
            for ruleNode in ruleNodes where attribute(ruleNode, "abstract") == "true" {
                if let id = attribute(ruleNode, "id") {
                    abstracts[id] = try AbstractRule(lets: ruleLets(ruleNode), assertions: ruleAssertions(ruleNode))
                }
            }
            let rules = try ruleNodes
                .filter { attribute($0, "abstract") != "true" }
                .compactMap { try rule($0, abstracts) }
            return try SchematronPattern(id: attribute(node, "id"), lets: ruleLets(node), rules: rules)
        }

        private static func rule(_ node: PureXML.Model.TreeNode, _ abstracts: [String: AbstractRule]) throws -> SchematronRule? {
            guard let context = attribute(node, "context") else { return nil }
            var lets = try ruleLets(node)
            var assertions = try ruleAssertions(node)
            // An <extends rule="id"> prepends the abstract rule's lets and
            // assertions, so the concrete rule extends rather than replaces them.
            for ext in children(node, localName: "extends") {
                guard let id = attribute(ext, "rule"), let base = abstracts[id] else { continue }
                lets = base.lets + lets
                assertions = base.assertions + assertions
            }
            return try SchematronRule(context: PureXML.XPath.Query(contextExpression(context)), lets: lets, assertions: assertions)
        }

        private static func ruleLets(_ node: PureXML.Model.TreeNode) throws -> [SchematronLet] {
            try children(node, localName: "let").compactMap(letBinding)
        }

        private static func ruleAssertions(_ node: PureXML.Model.TreeNode) throws -> [SchematronAssertion] {
            try node.children
                .filter { $0.kind == .element && isAssertion($0) }
                .compactMap(assertion)
        }

        private static func letBinding(_ node: PureXML.Model.TreeNode) throws -> SchematronLet? {
            guard let name = attribute(node, "name"), let value = attribute(node, "value") else { return nil }
            return try SchematronLet(name: name, value: PureXML.XPath.Query(value))
        }

        private static func assertion(_ node: PureXML.Model.TreeNode) throws -> SchematronAssertion? {
            guard let test = attribute(node, "test") else { return nil }
            let referenced = attribute(node, "diagnostics")?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
            return try SchematronAssertion(
                isReport: node.name?.localName == "report",
                test: PureXML.XPath.Query(test),
                message: messageParts(node),
                diagnostics: referenced,
            )
        }

        /// The `<diagnostic id=>` message templates, keyed by id.
        private static func diagnostics(_ root: PureXML.Model.TreeNode) throws -> [String: [SchematronMessagePart]] {
            var table: [String: [SchematronMessagePart]] = [:]
            for diagnostic in descendants(root, localName: "diagnostic") {
                if let id = attribute(diagnostic, "id") {
                    table[id] = try messageParts(diagnostic)
                }
            }
            return table
        }

        /// Builds an assertion message template from a node's children: text nodes
        /// become literal parts, `<value-of select=>` an XPath part, and `<name>` a
        /// context-name part. The parts render against the context node at
        /// validation time.
        private static func messageParts(_ node: PureXML.Model.TreeNode) throws -> [SchematronMessagePart] {
            var parts: [SchematronMessagePart] = []
            for child in node.children {
                if child.kind == .text || child.kind == .cdata {
                    parts.append(.text(child.value))
                } else if child.kind == .element, child.name?.localName == "value-of", let select = attribute(child, "select") {
                    try parts.append(.valueOf(PureXML.XPath.Query(select)))
                } else if child.kind == .element, child.name?.localName == "name" {
                    parts.append(.name)
                }
            }
            return parts
        }

        private static func isAssertion(_ node: PureXML.Model.TreeNode) -> Bool {
            node.name?.localName == "assert" || node.name?.localName == "report"
        }

        /// A relative context selects matching nodes anywhere, so it is searched
        /// from the document via `//`; an absolute context is used as written.
        private static func contextExpression(_ context: String) -> String {
            context.hasPrefix("/") ? context : "//" + context
        }

        private static func attribute(_ node: PureXML.Model.TreeNode, _ name: String) -> String? {
            node.attributes.first { $0.name.localName == name || $0.name.description == name }?.value
        }

        private static func children(_ node: PureXML.Model.TreeNode, localName: String) -> [PureXML.Model.TreeNode] {
            node.children.filter { $0.kind == .element && $0.name?.localName == localName }
        }

        private static func descendants(_ node: PureXML.Model.TreeNode, localName: String) -> [PureXML.Model.TreeNode] {
            var result: [PureXML.Model.TreeNode] = []
            for child in node.children {
                if child.kind == .element, child.name?.localName == localName {
                    result.append(child)
                }
                result.append(contentsOf: descendants(child, localName: localName))
            }
            return result
        }
    }
}
