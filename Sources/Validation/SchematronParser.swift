extension PureXML.Validation {
    /// Parses a Schematron schema document into patterns. Namespace-agnostic: it
    /// matches the `schema`, `pattern`, `rule`, `assert`, and `report` elements by
    /// local name, so both the ISO and the legacy Schematron namespaces work.
    enum SchematronParser {
        static func parse(_ xml: String) throws -> [SchematronPattern] {
            let root = try PureXML.parseTree(xml)
            return try descendants(root, localName: "pattern").map(pattern)
        }

        private static func pattern(_ node: PureXML.Model.TreeNode) throws -> SchematronPattern {
            try SchematronPattern(rules: children(node, localName: "rule").compactMap(rule))
        }

        private static func rule(_ node: PureXML.Model.TreeNode) throws -> SchematronRule? {
            guard let context = attribute(node, "context") else { return nil }
            let assertions = try node.children
                .filter { $0.kind == .element && isAssertion($0) }
                .compactMap(assertion)
            return try SchematronRule(context: PureXML.XPath.Query(contextExpression(context)), assertions: assertions)
        }

        private static func assertion(_ node: PureXML.Model.TreeNode) throws -> SchematronAssertion? {
            guard let test = attribute(node, "test") else { return nil }
            let isReport = node.name?.localName == "report"
            return try SchematronAssertion(
                isReport: isReport,
                test: PureXML.XPath.Query(test),
                message: node.stringValue.trimmingXMLWhitespace(),
            )
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
