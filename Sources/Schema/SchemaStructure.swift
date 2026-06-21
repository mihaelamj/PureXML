extension PureXML.Schema.XSDParser {
    /// The XML Schema namespace; only elements in it are schema vocabulary, so
    /// foreign elements (and annotation content) are not structurally checked.
    static let xsdNamespace = "http://www.w3.org/2001/XMLSchema"

    /// The schema-for-schemas child content model (XSD 1.0 Structures): the
    /// XSD-namespace element local names each component admits as children. The
    /// `restriction`/`extension` entries are the permissive union across their
    /// simple/complex/simpleContent contexts, so this never rejects a child that
    /// is valid in some context; order beyond the leading annotation is not
    /// modelled here. Leaf components and facets admit only `annotation`.
    private static let allowedChildren: [String: Set<String>] = {
        let facets: Set = [
            "minExclusive", "minInclusive", "maxExclusive", "maxInclusive", "totalDigits",
            "fractionDigits", "length", "minLength", "maxLength", "enumeration", "whiteSpace", "pattern",
        ]
        var table: [String: Set<String>] = [
            "schema": ["include", "import", "redefine", "annotation", "simpleType", "complexType", "group", "attributeGroup", "element", "attribute", "notation"],
            "complexType": ["annotation", "simpleContent", "complexContent", "group", "all", "choice", "sequence", "attribute", "attributeGroup", "anyAttribute"],
            "simpleContent": ["annotation", "restriction", "extension"],
            "complexContent": ["annotation", "restriction", "extension"],
            "simpleType": ["annotation", "restriction", "list", "union"],
            "element": ["annotation", "simpleType", "complexType", "unique", "key", "keyref"],
            "attribute": ["annotation", "simpleType"],
            "attributeGroup": ["annotation", "attribute", "attributeGroup", "anyAttribute"],
            "group": ["annotation", "all", "choice", "sequence"],
            "all": ["annotation", "element"],
            "choice": ["annotation", "element", "group", "choice", "sequence", "any"],
            "sequence": ["annotation", "element", "group", "choice", "sequence", "any"],
            "restriction": Set(["annotation", "simpleType", "group", "all", "choice", "sequence", "attribute", "attributeGroup", "anyAttribute"]).union(facets),
            "extension": ["annotation", "group", "all", "choice", "sequence", "attribute", "attributeGroup", "anyAttribute"],
            "unique": ["annotation", "selector", "field"],
            "key": ["annotation", "selector", "field"],
            "keyref": ["annotation", "selector", "field"],
            "annotation": ["appinfo", "documentation"],
            "list": ["annotation", "simpleType"],
            "union": ["annotation", "simpleType"],
            "redefine": ["annotation", "simpleType", "complexType", "group", "attributeGroup"],
        ]
        for leaf in ["selector", "field", "any", "anyAttribute", "notation", "import", "include"] + Array(facets) {
            table[leaf] = ["annotation"]
        }
        return table
    }()

    /// Components whose annotation may be repeated and interspersed (XSD 1.0:
    /// `schema` and `redefine`); everywhere else `annotation` is `annotation?`
    /// and must be the first child.
    private static let multipleAnnotation: Set<String> = ["schema", "redefine"]

    /// Schema-validity findings for the structural content of a schema document:
    /// each XSD-namespace element's XSD-namespace children must be admitted by the
    /// schema-for-schemas content model, the single `annotation` (where allowed
    /// once) must be first, and an identity constraint needs a selector and field.
    /// Walks the one document rooted at `schema`, skipping foreign content.
    static func structureErrors(_ schema: XSDTree) -> [String] {
        structureFindings(schema).map(\.reason)
    }

    static func structureFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        let bindings = PureXML.Schema.XSDNode.namespaceBindings(of: schema)
        collectStructure(schema, bindings: bindings, into: &findings)
        append(simpleTypeVarietyFacetErrors(schema), at: schema, into: &findings)
        findings += valueConstraintFindings(schema)
        append(topLevelDeclarationErrors(schema), at: schema, into: &findings)
        append(nestedNamedDefinitionErrors(schema), at: schema, into: &findings)
        append(anySimpleTypeRestrictionErrors(schema) + anySimpleTypeFacetErrors(schema), at: schema, into: &findings)
        append(emptyNamespaceErrors(schema) + allGroupReferenceMaxOccursErrors(schema), at: schema, into: &findings)
        return findings
    }

    private static func append(
        _ messages: [String],
        at node: XSDTree,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        for message in messages {
            findings.append(PureXML.Schema.SchemaLocatedFinding(reason: message, node: node))
        }
    }

    private static func collectStructure(
        _ node: XSDTree,
        bindings: [String: String],
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        let children = PureXML.Schema.XSDNode.elementChildren(node)
        var currentBindings = bindings
        for attribute in node.attributes {
            if attribute.name.prefix == "xmlns" {
                currentBindings[attribute.name.localName] = attribute.value
            } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                currentBindings[""] = attribute.value
            }
        }
        if node.name?.namespaceURI == xsdNamespace, let local {
            append(attributeValueErrors(node, bindings: currentBindings), at: node, into: &findings)
            append(xsdNamespaceAttributeErrors(node, bindings: currentBindings), at: node, into: &findings)
            append(occurrenceOrderErrors(node), at: node, into: &findings)
            append(attributeApplicabilityErrors(node, local: local), at: node, into: &findings)
            append(localElementErrors(node, local: local), at: node, into: &findings)
            let names = children.filter { $0.name?.namespaceURI == xsdNamespace }.compactMap(PureXML.Schema.XSDNode.localName)
            append(componentSpecificErrors(node, local: local, names: names), at: node, into: &findings)
        }
        if local == "appinfo" || local == "documentation" { return }
        for child in children {
            collectStructure(child, bindings: currentBindings, into: &findings)
        }
    }

    private static func componentSpecificErrors(_ node: XSDTree, local: String, names: [String]) -> [String] {
        var errors: [String] = []
        if let allowed = allowedChildren(for: local, node: node) {
            errors += childErrors(local: local, children: names, allowed: allowed)
        }
        errors += derivationControlErrors(node, local: local)
        errors += typeAndGroupErrors(node, local: local, names: names)
        errors += structuralErrors(node, local: local, names: names)
        return errors
    }

    private static func typeAndGroupErrors(_ node: XSDTree, local: String, names: [String]) -> [String] {
        var errors: [String] = []
        switch local {
        case "group" where PureXML.Schema.XSDNode.attribute(node, "name") != nil:
            errors += namedGroupErrors(names)
            errors += namedGroupOccurrenceErrors(node)
        case "complexType":
            errors += elementDeclsConsistentErrors(node)
            errors += complexTypeOrderErrors(node)
            errors += localComplexTypeNameErrors(node)
        case "complexContent":
            errors += complexContentOrderErrors(node)
        case "simpleContent":
            errors += simpleContentOrderErrors(node)
        case "selector", "field":
            errors += identityXPathErrors(node, local: local)
        case "unique", "key", "keyref":
            errors += identityConstraintContentErrors(names)
        default:
            break
        }
        return errors
    }

    private static func structuralErrors(_ node: XSDTree, local: String, names: [String]) -> [String] {
        switch local {
        case "any", "anyAttribute": wildcardNamespaceErrors(node)
        case "restriction":
            restrictionErrors(node, names: names)
        case "list":
            listErrors(node, names: names)
        case "schema":
            schemaChildrenOrderErrors(names)
        case "import":
            importErrors(node)
        case "include", "redefine":
            PureXML.Schema.XSDNode.attribute(node, "schemaLocation") == nil ? ["an '\(local)' must have a 'schemaLocation' attribute"] : []
        default:
            containerStructuralErrors(node, local: local, names: names)
        }
    }

    private static func containerStructuralErrors(_ node: XSDTree, local: String, names: [String]) -> [String] {
        switch local {
        case "element":
            elementChildrenErrors(node, names: names)
        case "attribute":
            attributeChildrenErrors(node, names: names)
        case "attributeGroup":
            attributeGroupChildrenErrors(node, names: names)
        case "group":
            groupChildrenErrors(node, names: names)
        case "all":
            allGroupLimitedErrors(node)
        default:
            []
        }
    }

    private static func allowedChildren(for local: String, node: XSDTree) -> Set<String>? {
        guard let allowed = allowedChildren[local] else { return nil }
        if local == "restriction", let parent = node.parent, parent.name?.namespaceURI == xsdNamespace, PureXML.Schema.XSDNode.localName(parent) == "simpleType" {
            return simpleTypeRestrictionAllowedChildren
        }
        return allowed
    }

    /// The enumerated value space of the schema-vocabulary attributes that take a
    /// fixed set of tokens. Each name has one meaning throughout XSD, so checking
    /// by local name is safe; `minOccurs`/`maxOccurs` are handled numerically.
    private static let attributeEnumerations: [String: Set<String>] = [
        "form": ["qualified", "unqualified"],
        "elementFormDefault": ["qualified", "unqualified"],
        "attributeFormDefault": ["qualified", "unqualified"],
        "use": ["optional", "prohibited", "required"],
        "processContents": ["skip", "lax", "strict"],
        "mixed": ["true", "false", "1", "0"],
        "abstract": ["true", "false", "1", "0"],
        "nillable": ["true", "false", "1", "0"],
    ]

    /// Findings for the unprefixed schema-vocabulary attributes on `node` whose
    /// value falls outside its fixed value space: an enumerated attribute with an
    /// unknown token, or `minOccurs`/`maxOccurs` that is not a `nonNegativeInteger`
    /// (`maxOccurs` also admits `unbounded`). A prefixed (foreign) attribute is the
    /// schema author's own and is not checked.
    private static func attributeValueErrors(_ node: XSDTree, bindings: [String: String]) -> [String] {
        node.attributes.compactMap { attribute -> String? in
            let prefix = attribute.name.prefix
            let name = attribute.name.localName
            let value = attribute.value
            if prefix == nil {
                if let err = attributeValueError(name, value) {
                    return err
                }
                if qnameAttributes.contains(name) {
                    return checkQNamePrefix(value, bindings: bindings)
                }
                if name == "memberTypes" {
                    return checkMemberTypesPrefixes(value, bindings: bindings)
                }
            } else if prefix == "xml" {
                if name == "lang" {
                    let trimmed = value.trimmingXMLWhitespace()
                    return PureXML.Schema.Lexical.isLanguage(trimmed) ? nil : "attribute 'xml:lang' has invalid value '\(value)'"
                } else if name == "space" {
                    let trimmed = value.trimmingXMLWhitespace()
                    return (trimmed == "default" || trimmed == "preserve") ? nil : "attribute 'xml:space' has invalid value '\(value)'"
                }
            }
            return nil
        }
    }

    /// Findings for attributes in the XML Schema namespace on a schema element
    /// (e.g. `xsd:type`): the schema vocabulary defines no namespaced attributes,
    /// so an XSD-namespace-qualified attribute is never valid (a foreign attribute
    /// in any OTHER namespace is the author's own and is left alone). Namespace
    /// declarations themselves (`xmlns`/`xmlns:p`) are not attributes here.
    private static func xsdNamespaceAttributeErrors(_ node: XSDTree, bindings: [String: String]) -> [String] {
        node.attributes.compactMap { attribute in
            guard let prefix = attribute.name.prefix, prefix != "xmlns", bindings[prefix] == xsdNamespace else { return nil }
            return "attribute '\(prefix):\(attribute.name.localName)' is in the XML Schema namespace, which defines no attributes"
        }
    }

    /// The schema-vocabulary attributes whose value is a single QName reference;
    /// each has one meaning throughout XSD, so they are recognised by local name.
    private static let qnameAttributes: Set<String> = ["type", "base", "ref", "itemType", "refer", "substitutionGroup"]

    /// The finding, if any, for one unprefixed schema-vocabulary attribute whose
    /// value falls outside its fixed value space: an enumerated token, an
    /// occurrence count, a `name` (NCName), or a QName reference. Only the lexical
    /// form is checked here; a QName's prefix is resolved elsewhere.
    private static func attributeValueError(_ name: String, _ raw: String) -> String? {
        let value = raw.trimmingXMLWhitespace()
        if let allowed = attributeEnumerations[name] {
            return allowed.contains(value) ? nil : "attribute '\(name)' has invalid value '\(raw)'"
        }
        switch name {
        case "minOccurs":
            return isNonNegativeInteger(value) ? nil : "attribute 'minOccurs' must be a nonNegativeInteger, not '\(raw)'"
        case "maxOccurs":
            return value == "unbounded" || isNonNegativeInteger(value) ? nil : "attribute 'maxOccurs' must be a nonNegativeInteger or 'unbounded', not '\(raw)'"
        case "name":
            return PureXML.Schema.Lexical.isNCName(value) ? nil : "attribute 'name' value '\(raw)' is not a valid NCName"
        case "memberTypes":
            let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
            return tokens.allSatisfy(PureXML.Schema.Lexical.isQName) ? nil : "attribute 'memberTypes' value '\(raw)' is not a list of QNames"
        case _ where qnameAttributes.contains(name):
            return PureXML.Schema.Lexical.isQName(value) ? nil : "attribute '\(name)' value '\(raw)' is not a valid QName"
        default:
            return nil
        }
    }

    private static func childErrors(local: String, children: [String], allowed: Set<String>) -> [String] {
        var errors: [String] = []
        for name in children where !allowed.contains(name) {
            errors.append("element '\(name)' is not allowed in '\(local)'")
        }
        if !multipleAnnotation.contains(local) {
            let annotations = children.count(where: { $0 == "annotation" })
            if annotations > 1 {
                errors.append("'\(local)' may have at most one annotation")
            } else if annotations == 1, children.first != "annotation" {
                errors.append("the annotation in '\(local)' must be the first child")
            }
        }
        if ["unique", "key", "keyref"].contains(local), !(children.contains("selector") && children.contains("field")) {
            errors.append("identity constraint '\(local)' requires a selector and at least one field")
        }
        if local == "complexType" {
            errors += complexTypeContentErrors(children)
        }
        if local == "simpleType" {
            errors += simpleTypeContentErrors(children)
        }
        return errors
    }

    /// The model groups and the attribute declarations a `complexType` may carry
    /// directly, used to enforce its content-model shape.
    private static let modelGroups: Set<String> = ["group", "all", "choice", "sequence"]
    private static let directAttributes: Set<String> = ["attribute", "attributeGroup", "anyAttribute"]

    /// Findings for a `complexType`'s direct content shape (XSD 1.0 Structures):
    /// its content is `simpleContent`, `complexContent`, or a model group followed
    /// by attributes, never a mix. So at most one of `simpleContent`/
    /// `complexContent`; when one is present, no model group and no direct
    /// attribute may sit beside it (they belong inside the derivation); and at most
    /// one model group. Children inside `simpleContent`/`complexContent` are not
    /// examined here, only the complexType's own children.
    private static func complexTypeContentErrors(_ children: [String]) -> [String] {
        let contentSpecs = children.count { $0 == "simpleContent" || $0 == "complexContent" }
        let groups = children.count { modelGroups.contains($0) }
        let attributes = children.count { directAttributes.contains($0) }
        if contentSpecs > 1 {
            return ["'complexType' may have only one of simpleContent or complexContent"]
        }
        if contentSpecs == 1, groups > 0 || attributes > 0 {
            return ["'complexType' with simpleContent or complexContent may not also have a model group or attribute"]
        }
        if groups > 1 {
            return ["'complexType' may have at most one model group"]
        }
        return []
    }

    /// The finding, if any, for a named model-group definition (`xs:group` with a
    /// `name`): its content is exactly one of `all`/`choice`/`sequence` (XSD 1.0
    /// Structures), so neither an empty group nor one with two compositors is
    /// valid. (A `group` *reference* carries no compositor child and is excluded
    /// by the caller.)
    private static func namedGroupErrors(_ children: [String]) -> [String] {
        let compositors = children.count { $0 == "all" || $0 == "choice" || $0 == "sequence" }
        return compositors == 1 ? [] : ["a named group must contain exactly one of all, choice, or sequence"]
    }

    /// The model-group and content-derivation elements through which a complex
    /// type's content model extends; the walk descends through these but never
    /// into an element's own type definition (a nested type is a separate model).
    private static let contentModelContainers: Set<String> = [
        "sequence", "choice", "all", "group", "complexContent", "simpleContent", "restriction", "extension",
    ]

    /// Findings for Element Declarations Consistent (cos-element-consistent): in a
    /// single complex type's content model, two element declarations with the same
    /// name must have the same type. Collects element particles across the content
    /// model (descending through model groups and content-derivation wrappers, not
    /// into a nested type), keyed by name; a name seen with more than one distinct
    /// type definition is a violation. (Substitution-group expansion is not folded
    /// in, an accepted under-rejection.)
    private static func elementDeclsConsistentErrors(_ complexType: XSDTree) -> [String] {
        var byName: [String: Set<String>] = [:]
        var inlineCount = 0
        collectElementDecls(complexType, into: &byName, inlineCount: &inlineCount)
        return byName.keys.sorted().compactMap { name in
            (byName[name]?.count ?? 0) > 1
                ? "element '\(name)' has inconsistent type definitions in the same content model"
                : nil
        }
    }

    private static func collectElementDecls(_ node: XSDTree, into byName: inout [String: Set<String>], inlineCount: inout Int) {
        for child in PureXML.Schema.XSDNode.elementChildren(node) where child.name?.namespaceURI == xsdNamespace {
            guard let local = PureXML.Schema.XSDNode.localName(child) else { continue }
            if local == "element" {
                if let name = PureXML.Schema.XSDNode.attribute(child, "name") {
                    byName[name, default: []].insert(elementTypeKey(child, inlineCount: &inlineCount))
                }
                // Do not descend into the element's own type definition.
            } else if contentModelContainers.contains(local) {
                collectElementDecls(child, into: &byName, inlineCount: &inlineCount)
            }
        }
    }

    /// A key identifying an element particle's type definition: its `type`
    /// reference by local name, a distinct token per inline (anonymous) type (two
    /// inline types are never the same definition), or a shared token when the
    /// element is untyped (the ur-type).
    private static func elementTypeKey(_ element: XSDTree, inlineCount: inout Int) -> String {
        if let type = PureXML.Schema.XSDNode.attribute(element, "type") {
            return "type:" + PureXML.Schema.XSDNode.stripPrefix(type.trimmingXMLWhitespace())
        }
        let hasInlineType = PureXML.Schema.XSDNode.elementChildren(element).contains {
            let local = PureXML.Schema.XSDNode.localName($0)
            return local == "complexType" || local == "simpleType"
        }
        if hasInlineType {
            inlineCount += 1
            return "inline:\(inlineCount)"
        }
        return "untyped"
    }
}
