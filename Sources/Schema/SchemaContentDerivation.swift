private typealias ContentDerivNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `cos-ct-extends.1.4.2.2`: a `complexContent` extension that adds
    /// element content (a model group) produces an element-only/mixed content type,
    /// so its base must have complex or empty content. A `simpleContent` base has a
    /// simple content type and cannot gain element content this way. An extension
    /// that adds only attributes keeps the base's simple content and is valid (it
    /// is the `complexContent`-around-`simpleContent` idiom), so the model group is
    /// required for the error. Resolved in this schema's own target namespace.
    static func simpleContentExtensionBaseFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ContentDerivNode.firstChild(content, named: "extension"),
                  extensionAddsElementContent(ext),
                  let base = ContentDerivNode.attribute(ext, "base"),
                  ContentDerivNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ContentDerivNode.stripPrefix(base)],
                  case .simpleContent = complex.content
            else { continue }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "a complexContent extension that adds element content may not extend '\(ContentDerivNode.stripPrefix(base))', which has simple content",
                node: ext,
            ))
        }
        return findings
    }

    /// XSD 1.0 `src-ct.2` / Derivation Valid (Restriction): the base of a
    /// `simpleContent` RESTRICTION must be a complex type (whose content is simple).
    /// A built-in (`xs:integer`, `xs:anySimpleType`) or a user `simpleType` base is
    /// invalid: a complex type with simple content is built by EXTENDING a simple
    /// type, never by restricting one through `simpleContent`. Self-contained schema
    /// only; a foreign or unresolved base is left alone.
    static func simpleContentRestrictionBaseFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let restriction = ContentDerivNode.firstChild(content, named: "restriction"),
                  let base = ContentDerivNode.attribute(restriction, "base")
            else { continue }
            let namespace = ContentDerivNode.referenceNamespace(base, bindings)
            let baseName = ContentDerivNode.stripPrefix(base)
            if namespace == xsdNamespace {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a simpleContent restriction's base must be a complex type, not the built-in simple type '\(baseName)'",
                    node: restriction,
                ))
            } else if namespace == context.targetNamespace, case .simple? = types[baseName] {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a simpleContent restriction's base must be a complex type, not the simple type '\(baseName)'",
                    node: restriction,
                ))
            }
        }
        return findings
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
    static func simpleContentRestrictionTypeFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let restriction = ContentDerivNode.firstChild(content, named: "restriction"),
                  let inline = ContentDerivNode.firstChild(restriction, named: "simpleType"),
                  let base = ContentDerivNode.attribute(restriction, "base")
            else { continue }
            let bindings = namespaceBindingsInScope(of: restriction, defaultBindings: context.namespaceBindings)
            let namespace = ContentDerivNode.referenceNamespace(base, bindings)
            let baseName = ContentDerivNode.stripPrefix(base)
            guard namespace == context.targetNamespace,
                  case let .complex(complex)? = types[baseName],
                  case let .simpleContent(baseSimpleType) = complex.content
            else { continue }
            let derivedSimpleType = scopedSimpleType(inline, context)
            if !isSimpleTypeRestrictionOK(derived: derivedSimpleType, base: baseSimpleType) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "the inline simpleType in a simpleContent restriction is not a valid restriction of base type '\(baseName)'",
                    node: restriction,
                ))
            }
        }
        return findings
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
    static func complexContentBaseKindFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "complexContent") {
            let isRestriction = ContentDerivNode.firstChild(content, named: "restriction") != nil
            guard let derivation = ContentDerivNode.firstChild(content, named: "extension")
                ?? ContentDerivNode.firstChild(content, named: "restriction"),
                let base = ContentDerivNode.attribute(derivation, "base")
            else { continue }
            let namespace = ContentDerivNode.referenceNamespace(base, bindings)
            let baseName = ContentDerivNode.stripPrefix(base)
            if namespace == context.targetNamespace, let local = types[baseName] {
                if case .simple = local {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "a complexContent base must be a complex type, not the simple type '\(baseName)'",
                        node: derivation,
                    ))
                } else if isRestriction, case let .complex(complex) = local, case .simpleContent = complex.content {
                    // cos-ct-restricts 5.2: a complexContent restriction's {content type}
                    // is element-only/mixed/empty (from its model group), which can never
                    // validly restrict a SIMPLE content type. So a complexContent
                    // restriction of a complex type that has simple content is invalid.
                    // (The extension direction has a valid attribute-only idiom and is
                    // handled by simpleContentExtensionBaseFindings, so it is not flagged
                    // here.) Catches particlesZ039.
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "a complexContent restriction's base '\(baseName)' has simple content, which a complexContent restriction cannot restrict",
                        node: derivation,
                    ))
                }
            } else if namespace == xsdNamespace, types[baseName] == nil, baseName != "anyType" {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a complexContent base must be a complex type, not the built-in simple type '\(baseName)'",
                    node: derivation,
                ))
            }
        }
        return findings
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
    static func simpleContentExtensionBaseKindFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "simpleContent") {
            guard let ext = ContentDerivNode.firstChild(content, named: "extension"),
                  let base = ContentDerivNode.attribute(ext, "base")
            else { continue }
            let namespace = ContentDerivNode.referenceNamespace(base, bindings)
            let baseName = ContentDerivNode.stripPrefix(base)
            if namespace == context.targetNamespace, case let .complex(complex)? = types[baseName] {
                switch complex.content {
                case .simpleContent: break
                case .mixed, .elementOnly, .empty:
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "a simpleContent extension's base complex type '\(baseName)' must have simple content",
                        node: ext,
                    ))
                }
            } else if namespace == xsdNamespace, types[baseName] == nil, baseName == "anyType" {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a simpleContent extension's base must be a simple type or a complex type with simple content, not '\(baseName)'",
                    node: ext,
                ))
            }
        }
        return findings
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
    static func elementValueConstraintContentFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for element in descendants(schema, named: "element") where element.name?.namespaceURI == xsdNamespace {
            guard ContentDerivNode.attribute(element, "fixed") != nil || ContentDerivNode.attribute(element, "default") != nil,
                  valueConstraintForbiddenByContent(element, bindings, context, types)
            else { continue }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "an element with a 'default' or 'fixed' value must have simple or mixed content, not element-only or empty content",
                node: element,
            ))
        }
        return findings
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
        if let inline = ContentDerivNode.firstChild(element, named: "complexType") {
            if ContentDerivNode.firstChild(inline, named: "simpleContent") != nil { return false }
            if ["true", "1"].contains(ContentDerivNode.attribute(inline, "mixed")) { return false }
            if ContentDerivNode.firstChild(inline, named: "complexContent") != nil { return false }
            return ["all", "sequence", "choice", "group"].contains { ContentDerivNode.firstChild(inline, named: $0) != nil }
        }
        guard let typeName = ContentDerivNode.attribute(element, "type") else { return false }
        let namespace = ContentDerivNode.referenceNamespace(typeName, bindings)
        let local = ContentDerivNode.stripPrefix(typeName)
        if namespace == xsdNamespace { return false }
        guard namespace == context.targetNamespace, case let .complex(complex)? = types[local] else { return false }
        switch complex.content {
        case .elementOnly, .empty: return true
        case .simpleContent, .mixed: return false
        }
    }

    /// XSD 1.0 `cos-ct-extends.1.4.3.2.2.1`: an explicit `mixed` on a
    /// `complexContent` extension must match the base. If `mixed` is omitted, an
    /// extension with no element particle inherits the base content unchanged
    /// (`ctZ012b`), while an extension that adds element content uses the schema
    /// default `false` (`ctZ010d`). Checked for a self-contained schema, and only
    /// when the base content is definitely element-only or mixed (an empty or
    /// simple-content base is governed by other rules and is left alone).
    static func extensionMixedAgreementFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "complexContent") {
            guard let ext = ContentDerivNode.firstChild(content, named: "extension"),
                  let base = ContentDerivNode.attribute(ext, "base"),
                  ContentDerivNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[ContentDerivNode.stripPrefix(base)]
            else { continue }
            let baseIsMixed: Bool
            switch complex.content {
            case .mixed: baseIsMixed = true
            case .elementOnly: baseIsMixed = false
            case .empty, .simpleContent: continue
            }
            guard let derivedMixed = declaredMixed(content, addsElementContent: extensionAddsElementContent(ext)) else { continue }
            if baseIsMixed != derivedMixed {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a complexContent extension of '\(ContentDerivNode.stripPrefix(base))' must have the same mixed setting as its base",
                    node: ext,
                ))
            }
        }
        return findings
    }

    /// The declared `mixed` value of a `complexContent` derivation. An omitted
    /// value matters only when the extension adds element content; otherwise the
    /// base content is inherited unchanged and there is no mixedness conflict.
    private static func declaredMixed(_ complexContent: XSDTree, addsElementContent: Bool) -> Bool? {
        if let own = ContentDerivNode.attribute(complexContent, "mixed") { return own == "true" || own == "1" }
        if let parent = complexContent.parent, let outer = ContentDerivNode.attribute(parent, "mixed") { return outer == "true" || outer == "1" }
        return addsElementContent ? false : nil
    }
}
