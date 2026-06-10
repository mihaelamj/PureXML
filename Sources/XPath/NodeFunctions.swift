extension PureXML.XPath {
    /// The XPath 1.0 node-set, boolean, and number functions beyond the core set:
    /// `id`, `local-name`, `namespace-uri`, `name`, `lang`, `sum`, `floor`,
    /// `ceiling`, and `round`.
    ///
    /// Without a DTD the XPath context cannot know which attributes are of type
    /// ID, so `id()` matches elements by an attribute named `id` or `xml:id`, the
    /// near-universal convention.
    enum NodeFunctions {
        nonisolated(unsafe) static let table = FunctionTable([
            "local-name": { arguments, context in .string(named(arguments, context)?.localName ?? "") },
            "name": { arguments, context in .string(named(arguments, context)?.description ?? "") },
            "namespace-uri": { arguments, context in .string(named(arguments, context)?.namespaceURI ?? "") },
            "id": { arguments, context in .nodeSet(identified(arguments.first, context)) },
            "lang": { arguments, context in .boolean(matchesLang(context.node, arguments.first?.string ?? "")) },
            "sum": { arguments, _ in
                guard let nodes = arguments.first?.nodes else {
                    throw PureXML.XPath.QueryError.invalidArguments("sum() requires a node-set")
                }
                return .number(nodes.reduce(0) { $0 + PureXML.XPath.Value.parseNumber($1.stringValue) })
            },
            "floor": { arguments, _ in .number((arguments.first?.number ?? .nan).rounded(.down)) },
            "ceiling": { arguments, _ in .number((arguments.first?.number ?? .nan).rounded(.up)) },
            "round": { arguments, _ in .number(PureXML.XPath.StringFunctions.rounded(arguments.first?.number ?? .nan)) },
        ])

        private static func named(_ arguments: [Value], _ context: EvaluationContext) -> PureXML.Model.QualifiedName? {
            target(arguments, context)?.qualifiedName
        }

        private static func target(_ arguments: [Value], _ context: EvaluationContext) -> Node? {
            if arguments.isEmpty { return context.node }
            return arguments.first?.nodes?.firstInDocumentOrder()
        }

        private static func identified(_ argument: Value?, _ context: EvaluationContext) -> [Node] {
            let tokens = idTokens(argument)
            guard !tokens.isEmpty, let root = rootTreeNode(of: context.node) else { return [] }
            var result: [Node] = []
            collect(root, tokens: tokens, into: &result)
            return result
        }

        private static func idTokens(_ argument: Value?) -> Set<String> {
            guard let argument else { return [] }
            let strings: [String] = if case let .nodeSet(nodes) = argument {
                nodes.map(\.stringValue)
            } else {
                [argument.string]
            }
            return Set(strings.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) })
        }

        private static func collect(_ tree: PureXML.Model.TreeNode, tokens: Set<String>, into result: inout [Node]) {
            if tree.kind == .element, let identifier = idValue(of: tree), tokens.contains(identifier) {
                result.append(.tree(tree))
            }
            for child in tree.children {
                collect(child, tokens: tokens, into: &result)
            }
        }

        private static func idValue(of tree: PureXML.Model.TreeNode) -> String? {
            tree.attributes.first { attribute in
                let name = attribute.name
                return name.description == "id" || name.description == "xml:id"
            }?.value
        }

        private static func matchesLang(_ node: Node, _ wanted: String) -> Bool {
            guard let language = inheritedLang(node) else { return false }
            let lowered = language.lowercased()
            let target = wanted.lowercased()
            return lowered == target || lowered.hasPrefix(target + "-")
        }

        private static func inheritedLang(_ node: Node) -> String? {
            var current: Node? = node
            while let here = current {
                if case let .tree(tree) = here, let language = langAttribute(of: tree) {
                    return language
                }
                current = here.parent
            }
            return nil
        }

        private static func langAttribute(of tree: PureXML.Model.TreeNode) -> String? {
            tree.attributes.first { $0.name.description == "xml:lang" }?.value
        }

        private static func rootTreeNode(of node: Node) -> PureXML.Model.TreeNode? {
            var current = node
            while let parent = current.parent {
                current = parent
            }
            return current.treeNode
        }
    }
}
