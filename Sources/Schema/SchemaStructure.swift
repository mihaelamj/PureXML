extension PureXML.Schema.XSDParser {
    /// The XML Schema namespace; only elements in it are schema vocabulary, so
    /// foreign elements (and annotation content) are not structurally checked.
    private static let xsdNamespace = "http://www.w3.org/2001/XMLSchema"

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

    private static func collectStructure(_ node: XSDTree, into errors: inout [String]) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        let children = PureXML.Schema.XSDNode.elementChildren(node)
        if node.name?.namespaceURI == xsdNamespace {
            errors += attributeValueErrors(node)
            if let local, let allowed = allowedChildren[local] {
                let names = children.filter { $0.name?.namespaceURI == xsdNamespace }.compactMap(PureXML.Schema.XSDNode.localName)
                errors += childErrors(local: local, children: names, allowed: allowed)
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
        return errors
    }
}
