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
    static func extensionAllGroupFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ExtAllNode.firstChild(content, named: "extension"),
                  let base = ExtAllNode.attribute(ext, "base"),
                  ExtAllNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ExtAllNode.stripPrefix(base)]
            else { continue }
            let baseName = ExtAllNode.stripPrefix(base)
            // The extension itself adds an `all` group over a base that already has
            // element content: the all would be nested in the extension sequence.
            if extensionHasAllGroup(ext), baseHasElementContent(complex.content) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "an 'all' group may not extend the type '\(baseName)', which has its own content; an all group must be the whole content model",
                    node: ext,
                ))
                continue
            }
            // The base's own content IS an `all` group and the extension adds
            // element content: the base's all is then nested in the sequence that
            // joins base and extension content, which is forbidden (cos-all-limited).
            if contentIsAllGroup(complex.content), extensionAddsElementContent(ext) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "the type '\(baseName)' has an 'all' group as its whole content and may not be extended with element content",
                    node: ext,
                ))
            }
        }
        return findings
    }

    /// Particle Valid (Restriction) for ANONYMOUS complex types: the named-type
    /// rule (`restrictionsAreSubsets`) is keyed by type name and so never sees an
    /// inline `complexType` that derives by `complexContent` restriction (the
    /// common `<element><complexType><complexContent><restriction base="...">`
    /// shape). This walks those, compiles each restricting type, resolves its base
    /// in this schema's own target namespace, and runs the same subset check. Only a
    /// self-contained schema is examined; the same `ParticleRestriction.violation`
    /// used for named types keeps the false-positive profile identical.
    static func anonymousRestrictionFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
        _ derivation: [String: PureXML.Schema.TypeDerivation],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for complexType in descendants(schema, named: "complexType") where ExtAllNode.attribute(complexType, "name") == nil {
            guard let content = ExtAllNode.firstChild(complexType, named: "complexContent"),
                  let restriction = ExtAllNode.firstChild(content, named: "restriction"),
                  let baseRef = ExtAllNode.attribute(restriction, "base"),
                  ExtAllNode.referenceNamespace(baseRef, bindings) == context.targetNamespace,
                  case let .complex(base)? = types[ExtAllNode.stripPrefix(baseRef)]
            else { continue }
            let restricted = PureXML.Schema.XSDParser.complexType(complexType, context)
            if let reason = PureXML.Schema.ParticleRestriction.violation(
                restricted: restricted.content,
                base: base.content,
                types: types,
                derivation: derivation,
            ) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "an anonymous complex type is not a valid restriction of '\(ExtAllNode.stripPrefix(baseRef))': \(reason)",
                    node: restriction,
                ))
            }
        }
        return findings
    }

    /// Whether a content type's whole content model is a NON-EMPTY `all` group. An
    /// empty `<all/>` contributes no content (the sibling rule treats extending
    /// empty content as valid), so it is not flagged.
    private static func contentIsAllGroup(_ content: PureXML.Schema.ContentType) -> Bool {
        switch content {
        case let .elementOnly(particle), let .mixed(particle):
            guard case let .group(group) = particle.term, group.compositor == .all else { return false }
            return !PureXML.Schema.ParticleRestriction.contentFree(particle)
        case .empty, .simpleContent:
            return false
        }
    }

    /// Whether a `complexContent` extension adds element content: an `element` or
    /// a wildcard `any` somewhere in its model group. An empty group (`<sequence/>`)
    /// or an attribute-only extension adds no element content, so it keeps the
    /// base's simple content and is not flagged. Shared with the content-derivation
    /// checkers in `SchemaContentDerivation.swift`, so it is module-internal.
    static func extensionAddsElementContent(_ extension: XSDTree) -> Bool {
        let hasElement = descendants(`extension`, named: "element").contains { $0.name?.namespaceURI == xsdNamespace }
        let hasWildcard = descendants(`extension`, named: "any").contains { $0.name?.namespaceURI == xsdNamespace }
        return hasElement || hasWildcard
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
