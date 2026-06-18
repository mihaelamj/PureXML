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
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
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
                errors.append("an 'all' group may not extend the type '\(baseName)', which has its own content; an all group must be the whole content model")
                continue
            }
            // The base's own content IS an `all` group and the extension adds
            // element content: the base's all is then nested in the sequence that
            // joins base and extension content, which is forbidden (cos-all-limited).
            if contentIsAllGroup(complex.content), extensionAddsElementContent(ext) {
                errors.append("the type '\(baseName)' has an 'all' group as its whole content and may not be extended with element content")
            }
        }
        return errors
    }

    /// Particle Valid (Restriction) for ANONYMOUS complex types: the named-type
    /// rule (`restrictionsAreSubsets`) is keyed by type name and so never sees an
    /// inline `complexType` that derives by `complexContent` restriction (the
    /// common `<element><complexType><complexContent><restriction base="...">`
    /// shape). This walks those, compiles each restricting type, resolves its base
    /// in this schema's own target namespace, and runs the same subset check. Only a
    /// self-contained schema is examined; the same `ParticleRestriction.violation`
    /// used for named types keeps the false-positive profile identical.
    static func anonymousRestrictionErrors(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
        _ derivation: [String: PureXML.Schema.TypeDerivation],
    ) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
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
                errors.append("an anonymous complex type is not a valid restriction of '\(ExtAllNode.stripPrefix(baseRef))': \(reason)")
            }
        }
        return errors
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

    /// XSD 1.0 `cos-ct-extends.1.4.2.2`: a `complexContent` extension that adds
    /// element content (a model group) produces an element-only/mixed content type,
    /// so its base must have complex or empty content. A `simpleContent` base has a
    /// simple content type and cannot gain element content this way. An extension
    /// that adds only attributes keeps the base's simple content and is valid (it
    /// is the `complexContent`-around-`simpleContent` idiom), so the model group is
    /// required for the error. Resolved in this schema's own target namespace.
    static func simpleContentExtensionBaseErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ExtAllNode.firstChild(content, named: "extension"),
                  extensionAddsElementContent(ext),
                  let base = ExtAllNode.attribute(ext, "base"),
                  ExtAllNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ExtAllNode.stripPrefix(base)],
                  case .simpleContent = complex.content
            else { continue }
            errors.append("a complexContent extension that adds element content may not extend '\(ExtAllNode.stripPrefix(base))', which has simple content")
        }
        return errors
    }

    /// XSD 1.0 `src-ct.2` / Derivation Valid (Restriction): the base of a
    /// `simpleContent` RESTRICTION must be a complex type (whose content is simple).
    /// A built-in (`xs:integer`, `xs:anySimpleType`) or a user `simpleType` base is
    /// invalid: a complex type with simple content is built by EXTENDING a simple
    /// type, never by restricting one through `simpleContent`. Self-contained schema
    /// only; a foreign or unresolved base is left alone.
    static func simpleContentRestrictionBaseErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let restriction = ExtAllNode.firstChild(content, named: "restriction"),
                  let base = ExtAllNode.attribute(restriction, "base")
            else { continue }
            let namespace = ExtAllNode.referenceNamespace(base, bindings)
            let baseName = ExtAllNode.stripPrefix(base)
            if namespace == xsdNamespace {
                errors.append("a simpleContent restriction's base must be a complex type, not the built-in simple type '\(baseName)'")
            } else if namespace == context.targetNamespace, case .simple? = types[baseName] {
                errors.append("a simpleContent restriction's base must be a complex type, not the simple type '\(baseName)'")
            }
        }
        return errors
    }

    /// XSD 1.0 Derivation Valid (Restriction, Simple): when a `simpleContent`
    /// restriction supplies an inline `simpleType`, that inline type must itself be
    /// a valid restriction of the base complex type's simple content type. A list
    /// of `xs:int`, for example, is not a restriction of `xs:decimal` because it
    /// changes the variety from atomic to list (W3C msData particlesZ018).
    ///
    /// Only local, resolved complex bases with simple content are checked. Built-in,
    /// foreign, unresolved, and composed bases are left to the surrounding base-kind
    /// and cross-document rules so this cannot reject a schema whose base type is
    /// unknown to this compile pass.
    static func simpleContentRestrictionTypeErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        var errors: [String] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let restriction = ExtAllNode.firstChild(content, named: "restriction"),
                  let inline = ExtAllNode.firstChild(restriction, named: "simpleType"),
                  let base = ExtAllNode.attribute(restriction, "base")
            else { continue }
            let bindings = namespaceBindingsInScope(of: restriction, defaultBindings: context.namespaceBindings)
            let namespace = ExtAllNode.referenceNamespace(base, bindings)
            let baseName = ExtAllNode.stripPrefix(base)
            guard namespace == context.targetNamespace,
                  case let .complex(complex)? = types[baseName],
                  case let .simpleContent(baseSimpleType) = complex.content
            else { continue }
            let derivedSimpleType = scopedSimpleType(inline, context)
            if !isSimpleTypeRestrictionOK(derived: derivedSimpleType, base: baseSimpleType) {
                errors.append("the inline simpleType in a simpleContent restriction is not a valid restriction of base type '\(baseName)'")
            }
        }
        return errors
    }

    /// XSD 1.0 `src-ct.1`: the base of a `complexContent` derivation (restriction or
    /// extension) must be a COMPLEX type. The ur-type `xs:anyType` is complex and is
    /// the legitimate base of most complex types; every other XSD built-in, and a
    /// user `simpleType`, is a simple type and may not be a complexContent base. A
    /// LOCALLY-declared type takes precedence over the built-in reading: a schema may
    /// target the XSD namespace and define its own components there (the
    /// schema-for-schemas extends its own `xs:openAttrs`), so resolve `types` first
    /// and only fall back to the built-in table when there is no local declaration.
    /// Self-contained schema only; a foreign or unresolved base is left alone.
    static func complexContentBaseKindErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "complexContent") {
            guard let derivation = ExtAllNode.firstChild(content, named: "extension")
                ?? ExtAllNode.firstChild(content, named: "restriction"),
                let base = ExtAllNode.attribute(derivation, "base")
            else { continue }
            let namespace = ExtAllNode.referenceNamespace(base, bindings)
            let baseName = ExtAllNode.stripPrefix(base)
            if namespace == context.targetNamespace, let local = types[baseName] {
                if case .simple = local {
                    errors.append("a complexContent base must be a complex type, not the simple type '\(baseName)'")
                }
            } else if namespace == xsdNamespace, types[baseName] == nil, baseName != "anyType" {
                errors.append("a complexContent base must be a complex type, not the built-in simple type '\(baseName)'")
            }
        }
        return errors
    }

    /// XSD 1.0 `src-ct.2` (extension): the base of a `simpleContent` EXTENSION must be
    /// a simple type or a complex type whose content type is simple. A complex type
    /// with element-only, mixed, or empty content (including the ur-type
    /// `xs:anyType`) may not be a simpleContent extension base, since the result must
    /// have simple content. A LOCALLY-declared type takes precedence over the
    /// built-in reading (a schema may target the XSD namespace), so resolve `types`
    /// first. A simple-type base (built-in or user) is valid; only `xs:anyType` as a
    /// built-in, or a local complex type without simple content, is an error.
    /// Self-contained schema only; a foreign or unresolved base is left alone.
    static func simpleContentExtensionBaseKindErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let ext = ExtAllNode.firstChild(content, named: "extension"),
                  let base = ExtAllNode.attribute(ext, "base")
            else { continue }
            let namespace = ExtAllNode.referenceNamespace(base, bindings)
            let baseName = ExtAllNode.stripPrefix(base)
            if namespace == context.targetNamespace, case let .complex(complex)? = types[baseName] {
                switch complex.content {
                case .simpleContent: break
                case .mixed, .elementOnly, .empty:
                    errors.append("a simpleContent extension's base complex type '\(baseName)' must have simple content")
                }
            } else if namespace == xsdNamespace, types[baseName] == nil, baseName == "anyType" {
                errors.append("a simpleContent extension's base must be a simple type or a complex type with simple content, not '\(baseName)'")
            }
        }
        return errors
    }

    /// XSD 1.0 `cos-valid-default` / `e-props-correct`: an element with a `default`
    /// or `fixed` value constraint must have a content type that admits character
    /// data, i.e. a simple type or mixed content. An element whose type is (or whose
    /// inline complex type has) element-only or empty content may not carry a value
    /// constraint. Conservative by construction: it flags only a content type that is
    /// CERTAINLY element-only or empty. A simple type, mixed content, the ur-type
    /// `xs:anyType` (mixed), an untyped element (also `anyType`), a complexContent
    /// derivation (mixedness may be inherited), and a foreign or unresolved type are
    /// all left alone, so this cannot raise a false positive. Self-contained schema.
    static func elementValueConstraintContentErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for element in descendants(schema, named: "element") where element.name?.namespaceURI == xsdNamespace {
            guard ExtAllNode.attribute(element, "fixed") != nil || ExtAllNode.attribute(element, "default") != nil,
                  valueConstraintForbiddenByContent(element, bindings, context, types)
            else { continue }
            errors.append("an element with a 'default' or 'fixed' value must have simple or mixed content, not element-only or empty content")
        }
        return errors
    }

    /// Whether `element`'s content type is certainly element-only or empty, so a
    /// value constraint on it is invalid. Returns false (no error) for anything that
    /// admits character data or that cannot be resolved with certainty.
    private static func valueConstraintForbiddenByContent(
        _ element: XSDTree,
        _ bindings: [String: String],
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> Bool {
        if let inline = ExtAllNode.firstChild(element, named: "complexType") {
            if ExtAllNode.firstChild(inline, named: "simpleContent") != nil { return false }
            if ["true", "1"].contains(ExtAllNode.attribute(inline, "mixed")) { return false }
            if ExtAllNode.firstChild(inline, named: "complexContent") != nil { return false }
            return ["all", "sequence", "choice", "group"].contains { ExtAllNode.firstChild(inline, named: $0) != nil }
        }
        guard let typeName = ExtAllNode.attribute(element, "type") else { return false }
        let namespace = ExtAllNode.referenceNamespace(typeName, bindings)
        let local = ExtAllNode.stripPrefix(typeName)
        if namespace == xsdNamespace { return false }
        guard namespace == context.targetNamespace, case let .complex(complex)? = types[local] else { return false }
        switch complex.content {
        case .elementOnly, .empty: return true
        case .simpleContent, .mixed: return false
        }
    }

    /// XSD 1.0 `cos-ct-extends.1.4.3.2.2.1`: a `complexContent` extension's mixedness
    /// must match its base type's. The effective content joins the base content and
    /// the extension's, so a mixed extension may extend only a mixed base and an
    /// element-only extension only an element-only base. Checked for a self-contained
    /// schema, and only when the base content is definitely element-only or mixed (an
    /// empty or simple-content base is governed by other rules and is left alone).
    static func extensionMixedAgreementErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ExtAllNode.firstChild(content, named: "extension"),
                  let base = ExtAllNode.attribute(ext, "base"),
                  ExtAllNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ExtAllNode.stripPrefix(base)]
            else { continue }
            let baseIsMixed: Bool
            switch complex.content {
            case .mixed: baseIsMixed = true
            case .elementOnly: baseIsMixed = false
            case .empty, .simpleContent: continue
            }
            // An extension that does not state `mixed` inherits the base's, so there
            // is no conflict; only an EXPLICIT `mixed` that disagrees is invalid.
            guard let derivedMixed = explicitMixed(content) else { continue }
            if baseIsMixed != derivedMixed {
                errors.append("a complexContent extension of '\(ExtAllNode.stripPrefix(base))' must have the same mixed setting as its base")
            }
        }
        return errors
    }

    /// The EXPLICIT `mixed` of a `complexContent` derivation: its own `mixed`
    /// attribute when present, otherwise the enclosing `complexType`'s, or nil when
    /// neither states it (an extension then inherits its base's mixedness). `true`
    /// and `1` are mixed.
    private static func explicitMixed(_ complexContent: XSDTree) -> Bool? {
        if let own = ExtAllNode.attribute(complexContent, "mixed") { return own == "true" || own == "1" }
        if let parent = complexContent.parent, let outer = ExtAllNode.attribute(parent, "mixed") { return outer == "true" || outer == "1" }
        return nil
    }

    /// Whether a `complexContent` extension adds element content: an `element` or
    /// a wildcard `any` somewhere in its model group. An empty group (`<sequence/>`)
    /// or an attribute-only extension adds no element content, so it keeps the
    /// base's simple content and is not flagged.
    private static func extensionAddsElementContent(_ extension: XSDTree) -> Bool {
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
