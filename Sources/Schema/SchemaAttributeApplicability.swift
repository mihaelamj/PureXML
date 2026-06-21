extension PureXML.Schema.XSDParser {
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
    /// component, the `ref` exclusions (`ref` excludes `name` and `type`), and the
    /// `type`-excludes-inline-type exclusion. A prefixed (foreign-namespace)
    /// attribute and a namespace declaration are not the component's own and are
    /// not checked.
    static func attributeApplicabilityErrors(_ node: XSDTree, local: String) -> [String] {
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
        return errors + refAndNameExclusionErrors(node, local: local, present: present)
    }

    /// The exclusions a `ref`, a `type`, or a reserved name impose on an element or
    /// attribute, beyond the per-component allowed-attribute table: `ref` excludes
    /// `name`/`type` (and, on an element, the other declaration-only properties; on
    /// an attribute, `form`) and an inline type; a `type` excludes an inline type;
    /// and an attribute may not be named `xmlns` (no-xmlns).
    private static func refAndNameExclusionErrors(_ node: XSDTree, local: String, present: Set<String>) -> [String] {
        var errors: [String] = []
        if present.contains("ref"), present.contains("name") {
            errors.append("'\(local)' may not have both 'ref' and 'name'")
        }
        if present.contains("ref"), present.contains("type") {
            errors.append("'\(local)' may not have both 'ref' and 'type'")
        }
        // src-element.2.2: an element `ref` is a use of a global declaration, not a
        // declaration, so beyond name/type it may not carry the other
        // declaration-only properties (`minOccurs`/`maxOccurs`, the particle's own,
        // stay allowed).
        if local == "element", present.contains("ref") {
            for excluded in ["nillable", "default", "fixed", "form", "block"] where present.contains(excluded) {
                errors.append("'element' with a 'ref' may not also specify '\(excluded)'")
            }
        }
        // src-attribute.3.2: an attribute `ref` is a use of a global declaration, so
        // beyond name/type it may not carry `form` either (the form comes from the
        // referenced declaration). `use` and a value constraint stay allowed on the use.
        if local == "attribute", present.contains("ref"), present.contains("form") {
            errors.append("'attribute' with a 'ref' may not also specify 'form'")
        }
        // no-xmlns: the {name} of an attribute declaration may not match `xmlns`
        // (that name is reserved for namespace declarations).
        if local == "attribute", PureXML.Schema.XSDNode.attribute(node, "name") == "xmlns" {
            errors.append("an attribute declaration may not be named 'xmlns'")
        }
        // A `ref` likewise excludes an inline type definition: the type comes from the
        // referenced declaration.
        if present.contains("ref"), local == "element" || local == "attribute", hasInlineType(node, local) {
            errors.append("'\(local)' with a 'ref' may not have an inline type definition")
        }
        // src-element.3 / src-attribute.3-4: a `type` attribute and an inline
        // anonymous type definition are mutually exclusive. An attribute may carry
        // only an inline `simpleType`; an element may carry a `simpleType` or
        // `complexType`.
        if present.contains("type"), local == "element" || local == "attribute", hasInlineType(node, local) {
            errors.append("'\(local)' may not have both a 'type' attribute and an inline type definition")
        }
        return errors
    }

    /// A top-level declaration (a direct child of `schema`, or of a `redefine`) is a
    /// global component, not a local use, so the attributes that belong only to a
    /// local use are rejected: the schema-for-schemas `topLevelAttribute` excludes
    /// `use`/`form`/`ref`, and `topLevelElement` excludes `ref`/`form`/`minOccurs`/
    /// `maxOccurs` (a global element is a declaration, never a particle or a
    /// reference). The per-component applicability table is the permissive
    /// global/local union and cannot make this distinction; this scan supplies the
    /// global-only constraint.
    static func topLevelDeclarationFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        collectTopLevelDeclarationFindings(in: schema, into: &findings)
        for redefine in PureXML.Schema.XSDNode.elementChildren(schema) {
            guard PureXML.Schema.XSDNode.localName(redefine) == "redefine" else { continue }
            collectTopLevelDeclarationFindings(in: redefine, into: &findings)
        }
        return findings
    }

    private static let topLevelForbidden: [String: [String]] = [
        "attribute": ["use", "form", "ref"],
        "element": ["ref", "form", "minOccurs", "maxOccurs"],
        "group": ["ref", "minOccurs", "maxOccurs"],
        "attributeGroup": ["ref"],
    ]

    private static let namedTopLevelKinds: Set<String> = [
        "simpleType", "complexType", "group", "attributeGroup", "element", "attribute", "notation",
    ]

    private static func collectTopLevelDeclarationFindings(in container: XSDTree, into findings: inout [PureXML.Schema.SchemaLocatedFinding]) {
        for child in PureXML.Schema.XSDNode.elementChildren(container) {
            guard child.name?.namespaceURI == xsdNamespace,
                  let kind = PureXML.Schema.XSDNode.localName(child)
            else { continue }
            if namedTopLevelKinds.contains(kind), !hasUnprefixed(child, "name") {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a top-level '\(kind)' definition must have a 'name' attribute",
                    node: child,
                ))
            }
            if let forbidden = topLevelForbidden[kind] {
                for attribute in forbidden where hasUnprefixed(child, attribute) {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "a top-level '\(kind)' declaration may not specify '\(attribute)'",
                        node: child,
                    ))
                }
            }
        }
    }

    /// A LOCAL element declaration (an element particle, not a direct child of
    /// `schema`) is not a global declaration, so the global-only properties
    /// `abstract`, `final`, and `substitutionGroup` may not appear on it (XSD 1.0
    /// schema-for-schemas `localElement`). Their presence is invalid at any value,
    /// so `abstract="false"` on a local element is rejected as well as `"true"`.
    static func localElementErrors(_ node: XSDTree, local: String) -> [String] {
        guard local == "element",
              let parent = node.parent,
              PureXML.Schema.XSDNode.localName(parent) != "schema"
        else { return [] }
        var errors: [String] = []
        if PureXML.Schema.XSDNode.attribute(node, "name") == nil, PureXML.Schema.XSDNode.attribute(node, "ref") == nil {
            errors.append("a local element declaration must have a 'name' or a 'ref'")
        }
        for forbidden in ["abstract", "final", "substitutionGroup"] where hasUnprefixed(node, forbidden) {
            errors.append("a local element declaration may not specify '\(forbidden)'")
        }
        return errors
    }

    private static func hasUnprefixed(_ node: XSDTree, _ local: String) -> Bool {
        node.attributes.contains { $0.name.prefix == nil && $0.name.localName == local }
    }

    private static func hasInlineType(_ node: XSDTree, _ local: String) -> Bool {
        PureXML.Schema.XSDNode.elementChildren(node).contains { child in
            // Only an inline type in the XSD namespace counts; a foreign-namespace
            // child that happens to be named `complexType`/`simpleType` is not the
            // component's own type definition (foreign content is not checked here).
            guard child.name?.namespaceURI == xsdNamespace else { return false }
            let kind = PureXML.Schema.XSDNode.localName(child)
            return kind == "simpleType" || (local == "element" && kind == "complexType")
        }
    }
}
