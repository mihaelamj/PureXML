extension PureXML.XPath {
    /// The core XPath functions tied to the four-type model and predicates:
    /// `last`, `position`, `count`, `not`, `true`, `false`, `boolean`, `number`,
    /// and `string`. The broader library (string, node, and number functions)
    /// extends this table.
    enum CoreFunctions {
        static let table = FunctionTable([
            "last": { _, context in .number(Double(context.size)) },
            "position": { _, context in .number(Double(context.position)) },
            "count": { arguments, _ in
                guard let nodes = arguments.first?.nodes else {
                    throw PureXML.XPath.QueryError.invalidArguments("count() requires a node-set")
                }
                return .number(Double(nodes.count))
            },
            "not": { arguments, _ in .boolean(!(arguments.first?.boolean ?? false)) },
            "true": { _, _ in .boolean(true) },
            "false": { _, _ in .boolean(false) },
            "boolean": { arguments, _ in .boolean(arguments.first?.boolean ?? false) },
            "number": { arguments, context in
                if let first = arguments.first { return .number(first.number) }
                return .number(PureXML.XPath.Value.parseNumber(context.node.stringValue))
            },
            "string": { arguments, context in
                if let first = arguments.first { return .string(first.string) }
                return .string(context.node.stringValue)
            },
        ])
    }
}
