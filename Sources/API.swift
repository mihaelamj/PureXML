public extension PureXML {
    /// Parses an XML document into a ``Model/Node`` tree.
    ///
    /// The parser is still being built; this entry point currently raises
    /// ``Parsing/ParseError/notImplemented(_:)``. The serializer and model are
    /// usable today for building and emitting trees.
    static func parse(_ xml: String) throws -> Model.Node {
        try Parsing.Parser().parse(xml)
    }

    /// Serializes a ``Model/Node`` tree into XML with the selected options.
    static func serialize(
        _ node: Model.Node,
        options: Emitting.Options = .default,
    ) -> String {
        Emitting.Serializer(options: options).serialize(node)
    }

    /// Validates a parsed XML node with the default validation rules.
    @discardableResult
    static func validate(
        _ node: Model.Node,
        using validator: Validation.Validator = .init(),
        strict: Bool = true,
    ) throws -> [Validation.Issue] {
        try validator.validate(node, strict: strict)
    }
}
