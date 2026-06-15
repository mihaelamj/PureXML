private typealias ExtAllNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `cos-all-limited.1.2` reached through extension: an `xs:all` group
    /// must be the whole content model of a complex type. When a complex type
    /// extends a base that already has element content, the effective content model
    /// is `sequence(base content, extension content)`, so an `all` in the extension
    /// is nested in that sequence and is invalid. Such schemas were accepted.
    ///
    /// Detected from the compiled base type: the extension is rejected only when its
    /// base resolves (in this schema's own target namespace) to a complex type whose
    /// content is element-only or mixed. An empty base (extending it with an `all`
    /// makes the `all` the whole content, which is valid), a simple-content base, or
    /// an unresolved/foreign base is left alone. Checked for a self-contained schema.
    static func extensionAllGroupErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !hasExternalReference(schema) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ExtAllNode.firstChild(content, named: "extension"),
                  extensionHasAllGroup(ext),
                  let base = ExtAllNode.attribute(ext, "base"),
                  ExtAllNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ExtAllNode.stripPrefix(base)],
                  baseHasElementContent(complex.content)
            else { continue }
            errors.append("an 'all' group may not extend the type '\(ExtAllNode.stripPrefix(base))', which has its own content; an all group must be the whole content model")
        }
        return errors
    }

    private static func extensionHasAllGroup(_ extension: XSDTree) -> Bool {
        ExtAllNode.elementChildren(`extension`).contains { child in
            child.name?.namespaceURI == xsdNamespace && ExtAllNode.localName(child) == "all"
        }
    }

    /// Whether the base type's content would wrap an `all` extension in a sequence.
    /// Mixed content always does (a mixed base, even with an empty particle, may not
    /// be extended by an `all`, per the resolution of W3C Bug 6202). Element-only
    /// content does only when its particle can actually contribute a child: an
    /// explicit but empty model group (`<xs:sequence/>`) is effectively empty, and
    /// extending empty content with an `all` makes the `all` the whole content,
    /// which is valid. Empty and simple-content bases carry no element content.
    private static func baseHasElementContent(_ content: PureXML.Schema.ContentType) -> Bool {
        switch content {
        case .mixed: true
        case let .elementOnly(particle): !PureXML.Schema.ParticleRestriction.contentFree(particle)
        case .empty, .simpleContent: false
        }
    }
}
