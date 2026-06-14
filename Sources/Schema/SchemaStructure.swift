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
        var errors: [String] = []
        collectStructure(schema, into: &errors)
        return errors
    }

    /// The unprefixed attributes each XSD component admits (XSD 1.0 schema for
    /// schemas). The element/attribute entries are the permissive union across
    /// global and local use (so a context-only attribute like `form` or
    /// `minOccurs` is never wrongly flagged); `id` is admitted everywhere. An
    /// attribute from a foreign namespace (prefixed) is always allowed and is not
    /// listed here.
    private static let allowedAttributes: [String: Set<String>] = {
        let facetAttrs: Set = ["value", "fixed", "id"]
        var table: [String: Set<String>] = [
            "schema": ["targetNamespace", "version", "finalDefault", "blockDefault", "attributeFormDefault", "elementFormDefault", "id"],
            "element": ["name", "ref", "type", "minOccurs", "maxOccurs", "default", "fixed", "nillable", "abstract", "substitutionGroup", "final", "block", "form", "id"],
            "attribute": ["name", "ref", "type", "use", "default", "fixed", "form", "id"],
            "complexType": ["name", "abstract", "final", "block", "mixed", "id"],
            "simpleType": ["name", "final", "id"],
            "complexContent": ["mixed", "id"],
            "simpleContent": ["id"],
            "restriction": ["base", "id"],
            "extension": ["base", "id"],
            "group": ["name", "ref", "minOccurs", "maxOccurs", "id"],
            "attributeGroup": ["name", "ref", "id"],
            "sequence": ["minOccurs", "maxOccurs", "id"],
            "choice": ["minOccurs", "maxOccurs", "id"],
            "all": ["minOccurs", "maxOccurs", "id"],
            "any": ["namespace", "processContents", "minOccurs", "maxOccurs", "id"],
            "anyAttribute": ["namespace", "processContents", "id"],
            "unique": ["name", "id"],
            "key": ["name", "id"],
            "keyref": ["name", "refer", "id"],
            "selector": ["xpath", "id"],
            "field": ["xpath", "id"],
            "list": ["itemType", "id"],
            "union": ["memberTypes", "id"],
            "import": ["namespace", "schemaLocation", "id"],
            "include": ["schemaLocation", "id"],
            "redefine": ["schemaLocation", "id"],
            "notation": ["name", "public", "system", "id"],
            "annotation": ["id"],
        ]
        for facet in ["minExclusive", "minInclusive", "maxExclusive", "maxInclusive", "totalDigits", "fractionDigits", "length", "minLength", "maxLength", "whiteSpace"] {
            table[facet] = facetAttrs
        }
        for facet in ["enumeration", "pattern"] {
            table[facet] = ["value", "id"]
        }
        return table
    }()

    /// Findings for the unprefixed attributes on `node`: any not admitted by its
    /// component, and the `ref` exclusions (`ref` excludes `name` and `type`). A
    /// prefixed (foreign-namespace) attribute and a namespace declaration are not
    /// the component's own and are not checked.
    private static func attributeApplicabilityErrors(_ node: XSDTree, local: String) -> [String] {
        guard let allowed = allowedAttributes[local] else { return [] }
        var errors: [String] = []
        var present: Set<String> = []
        for attribute in node.attributes where attribute.name.prefix == nil && attribute.name.localName != "xmlns" {
            let name = attribute.name.localName
            present.insert(name)
            if !allowed.contains(name) {
                errors.append("attribute '\(name)' is not allowed on '\(local)'")
            }
        }
        if present.contains("ref"), present.contains("name") {
            errors.append("'\(local)' may not have both 'ref' and 'name'")
        }
        if present.contains("ref"), present.contains("type") {
            errors.append("'\(local)' may not have both 'ref' and 'type'")
        }
        return errors
    }

    private static func collectStructure(_ node: XSDTree, into errors: inout [String]) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        let children = PureXML.Schema.XSDNode.elementChildren(node)
        if node.name?.namespaceURI == xsdNamespace {
            errors += attributeValueErrors(node)
            errors += occurrenceOrderErrors(node)
            if let local { errors += attributeApplicabilityErrors(node, local: local) }
            let names = children.filter { $0.name?.namespaceURI == xsdNamespace }.compactMap(PureXML.Schema.XSDNode.localName)
            if let local, let allowed = allowedChildren[local] {
                errors += childErrors(local: local, children: names, allowed: allowed)
            }
            if local == "group", PureXML.Schema.XSDNode.attribute(node, "name") != nil {
                errors += namedGroupErrors(names)
            }
            if local == "complexType" {
                errors += elementDeclsConsistentErrors(node)
            }
            if local == "complexContent" {
                errors += complexContentOrderErrors(node)
            }
            if let local, local == "selector" || local == "field" {
                errors += identityXPathErrors(node, local: local)
            }
        }
        for child in children {
            collectStructure(child, into: &errors)
        }
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
    private static func attributeValueErrors(_ node: XSDTree) -> [String] {
        node.attributes.filter { $0.name.prefix == nil }.compactMap { attribute in
            attributeValueError(attribute.name.localName, attribute.value)
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

    /// Whether `value` is a lexical `nonNegativeInteger` (optional `+`, ASCII
    /// digits), independent of machine-integer range.
    private static func isNonNegativeInteger(_ value: String) -> Bool {
        var digits = Substring(value)
        if digits.first == "+" { digits = digits.dropFirst() }
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The finding, if any, for a particle whose `minOccurs` exceeds its
    /// `maxOccurs`. `unbounded` is never exceeded, and a malformed value is left
    /// to ``attributeValueError``; the comparison is by canonical magnitude, so it
    /// holds for occurrence counts beyond a machine integer.
    private static func occurrenceOrderErrors(_ node: XSDTree) -> [String] {
        guard let minRaw = PureXML.Schema.XSDNode.attribute(node, "minOccurs"),
              let maxRaw = PureXML.Schema.XSDNode.attribute(node, "maxOccurs")
        else { return [] }
        let minimum = minRaw.trimmingXMLWhitespace()
        let maximum = maxRaw.trimmingXMLWhitespace()
        guard maximum != "unbounded", isNonNegativeInteger(minimum), isNonNegativeInteger(maximum),
              exceeds(minimum, maximum)
        else { return [] }
        return ["minOccurs (\(minRaw)) exceeds maxOccurs (\(maxRaw))"]
    }

    /// Whether nonNegativeInteger lexical `lhs` is strictly greater than `rhs`,
    /// comparing canonical magnitude (sign and leading zeros stripped) by length
    /// then lexically, so it is independent of machine-integer range.
    private static func exceeds(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalMagnitude(lhs), right = canonicalMagnitude(rhs)
        return left.count != right.count ? left.count > right.count : left > right
    }

    private static func canonicalMagnitude(_ value: String) -> Substring {
        var digits = Substring(value)
        if digits.first == "+" { digits = digits.dropFirst() }
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : trimmed
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
