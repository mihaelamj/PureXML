public extension PureXML {
    /// Parses an XML document into a ``Model/Node`` tree.
    ///
    /// The parser is still being built; this entry point currently raises
    /// ``Parsing/ParseError/notImplemented(_:)``. The serializer and model are
    /// usable today for building and emitting trees.
    static func parse(
        _ xml: String,
        limits: Parsing.Limits = .default,
        resolver: Parsing.EntityResolver = .refusing,
    ) throws -> Model.Node {
        try Parsing.Parser().parse(xml, limits: limits, resolver: resolver)
    }

    /// Parses an XML document from an incremental character source into a
    /// ``Model/Node`` tree. The closure returns the next character or nil at end
    /// of input, so the document can arrive in chunks and is never held whole.
    static func parse(
        pulling pull: @escaping () -> Character?,
        limits: Parsing.Limits = .default,
    ) throws -> Model.Node {
        try Parsing.Parser().parse(pulling: pull, limits: limits)
    }

    /// Parses an XML document from raw bytes, detecting the encoding (UTF-8 or
    /// UTF-16, with or without a byte-order mark) before parsing.
    static func parse(bytes: [UInt8], limits: Parsing.Limits = .default) throws -> Model.Node {
        try Parsing.Parser().parse(bytes: bytes, limits: limits)
    }

    /// Returns a streaming ``Parsing/EventReader`` over an XML string. Pull events
    /// one at a time with `next()` to process documents without building a tree.
    static func events(
        _ xml: String,
        limits: Parsing.Limits = .default,
        resolver: Parsing.EntityResolver = .refusing,
    ) -> Parsing.EventReader {
        Parsing.EventReader(xml, limits: limits, resolver: resolver)
    }

    /// Parses a document, delivering SAX-style callbacks (the libxml2 SAX2 model)
    /// instead of building a tree.
    static func parse(_ xml: String, sax handler: Parsing.SAXHandler, limits: Parsing.Limits = .default) throws {
        try Parsing.Parser().parse(xml, sax: handler, limits: limits)
    }

    /// Returns a streaming ``Parsing/EventReader`` over raw bytes, detecting the
    /// encoding before streaming events.
    static func events(bytes: [UInt8], limits: Parsing.Limits = .default) throws -> Parsing.EventReader {
        try Parsing.EventReader(Parsing.ByteDecoder.decode(bytes), limits: limits)
    }

    /// Returns a streaming ``Parsing/EventReader`` over an incremental character
    /// source, for processing arbitrarily large or chunked input.
    static func events(
        pulling pull: @escaping () -> Character?,
        limits: Parsing.Limits = .default,
    ) -> Parsing.EventReader {
        Parsing.EventReader(pulling: pull, limits: limits)
    }

    /// Parses an XML document from an incremental byte source, decoding the
    /// encoding on the fly so the bytes are never fully buffered.
    static func parse(
        pullingBytes pull: @escaping () -> UInt8?,
        limits: Parsing.Limits = .default,
    ) throws -> Model.Node {
        try Parsing.Parser().parse(pullingBytes: pull, limits: limits)
    }

    /// Returns a streaming ``Parsing/EventReader`` over an incremental byte
    /// source, decoding the encoding on the fly.
    static func events(
        pullingBytes pull: @escaping () -> UInt8?,
        limits: Parsing.Limits = .default,
    ) -> Parsing.EventReader {
        var decoder = Parsing.StreamingDecoder(pullingBytes: pull)
        return Parsing.EventReader(pulling: { decoder.next() }, limits: limits)
    }

    /// Parses an XML document and validates its tree against the DTD content
    /// models declared in its internal subset, returning the validation issues.
    /// DTD processing must be enabled (`Limits(allowDoctype: true)`); without a
    /// DTD the result is empty.
    static func validateAgainstInternalDTD(
        _ xml: String,
        limits: Parsing.Limits = .init(allowDoctype: true),
        strict: Bool = false,
        resolver: Parsing.EntityResolver = .refusing,
    ) throws -> [Validation.Issue] {
        let parsed = try Parsing.Parser().parseWithDocumentType(xml, limits: limits, resolver: resolver)
        let schema = Validation.DTDSchema(parsed.documentType)
        return schema.validate(parsed.node, strict: strict)
    }

    /// Compiles and evaluates an XPath query over a node, returning the selected
    /// node-set. Compile once with ``XPath/Query`` to reuse a query.
    static func xpath(_ path: String, over node: Model.Node) throws -> [XPath.Selection] {
        try XPath.Query(path).evaluate(over: node)
    }

    /// Serializes a ``Model/Node`` tree into XML with the selected options.
    static func serialize(
        _ node: Model.Node,
        options: Emitting.Options = .default,
    ) -> String {
        Emitting.Serializer(options: options).serialize(node)
    }

    /// Returns a pull cursor (the libxml2 `xmlTextReader` model) over an XML
    /// string. Call `read()` to advance node by node, reading `nodeKind`, `name`,
    /// `value`, `depth`, and `attributes` at each step.
    static func reader(
        _ xml: String,
        limits: Parsing.Limits = .default,
        resolver: Parsing.EntityResolver = .refusing,
    ) -> Parsing.TextReader {
        Parsing.TextReader(xml, limits: limits, resolver: resolver)
    }

    /// Parses an XML document into a mutable, parent-aware ``Model/TreeNode`` for
    /// in-place editing (insert, remove, replace, copy, and upward navigation).
    /// Serialize the result back with `serialize(tree.node)`.
    static func parseTree(
        _ xml: String,
        limits: Parsing.Limits = .default,
        resolver: Parsing.EntityResolver = .refusing,
    ) throws -> Model.TreeNode {
        try Model.TreeNode(parse(xml, limits: limits, resolver: resolver))
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
