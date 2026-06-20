extension PureXML.Schema.XSDParser {
    static let simpleTypeRestrictionAllowedChildren: Set<String> = {
        let facets: Set = [
            "minExclusive", "minInclusive", "maxExclusive", "maxInclusive", "totalDigits",
            "fractionDigits", "length", "minLength", "maxLength", "enumeration", "whiteSpace", "pattern",
        ]
        return Set(["annotation", "simpleType"]).union(facets)
    }()

    static func checkQNamePrefix(_ qname: String, bindings: [String: String]) -> String? {
        let trimmed = qname.trimmingXMLWhitespace()
        guard PureXML.Schema.Lexical.isQName(trimmed) else { return nil }
        if let prefix = PureXML.Schema.XSDNode.prefix(trimmed) {
            if prefix == "xml" { return nil }
            if bindings[prefix] == nil {
                return "prefix '\(prefix)' is not bound"
            }
        }
        return nil
    }

    static func checkMemberTypesPrefixes(_ memberTypes: String, bindings: [String: String]) -> String? {
        let tokens = memberTypes.trimmingXMLWhitespace().split(whereSeparator: \.isWhitespace).map(String.init)
        for token in tokens {
            if let err = checkQNamePrefix(token, bindings: bindings) {
                return err
            }
        }
        return nil
    }

    static func isNonNegativeInteger(_ value: String) -> Bool {
        var digits = Substring(value)
        if digits.first == "+" { digits = digits.dropFirst() }
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// p-props-correct.1 (XSD 1.0 Structures 3.9.6): a particle's {min occurs} may
    /// not exceed its {max occurs}. Both default to 1 when the attribute is absent,
    /// so `minOccurs="2"` with no `maxOccurs` means 2 > 1 and is invalid, as is
    /// `maxOccurs="0"` with no `minOccurs` (1 > 0). `unbounded` is infinite and never
    /// exceeded; a non-integer lexical is a separate, already-reported error.
    static func occurrenceOrderErrors(_ node: XSDTree) -> [String] {
        let minRaw = PureXML.Schema.XSDNode.attribute(node, "minOccurs")
        let maxRaw = PureXML.Schema.XSDNode.attribute(node, "maxOccurs")
        guard minRaw != nil || maxRaw != nil else { return [] }
        let minimum = (minRaw ?? "1").trimmingXMLWhitespace()
        let maximum = (maxRaw ?? "1").trimmingXMLWhitespace()
        guard maximum != "unbounded", isNonNegativeInteger(minimum), isNonNegativeInteger(maximum),
              exceeds(minimum, maximum)
        else { return [] }
        return ["minOccurs (\(minRaw ?? "1")) exceeds maxOccurs (\(maxRaw ?? "1"))"]
    }

    /// cos-all-limited clause 2 (XSD 1.0 Structures 3.8.6): the {max occurs} of an
    /// `all` group must be 1 and its {min occurs} 0 or 1, and the {max occurs} of
    /// every particle the group contains must be 0 or 1. `unbounded`, or any value
    /// above 1, is invalid. (The lexical validity of the values is checked
    /// elsewhere; this orders only well-formed non-negative integers.)
    static func allGroupLimitedErrors(_ node: XSDTree) -> [String] {
        var errors: [String] = []
        func limited(_ value: String?, allowZero: Bool, what: String) {
            guard let raw = value?.trimmingXMLWhitespace() else { return }
            let allowed: Set<Substring> = allowZero ? ["0", "1"] : ["1"]
            if raw == "unbounded" || (isNonNegativeInteger(raw) && !allowed.contains(canonicalMagnitude(raw))) {
                errors.append("\(what) must be \(allowZero ? "0 or 1" : "1")")
            }
        }
        limited(PureXML.Schema.XSDNode.attribute(node, "maxOccurs"), allowZero: false, what: "the maxOccurs of an all group")
        limited(PureXML.Schema.XSDNode.attribute(node, "minOccurs"), allowZero: true, what: "the minOccurs of an all group")
        let xsd = PureXML.Schema.XSDParser.xsdNamespace
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            guard child.name?.namespaceURI == xsd, PureXML.Schema.XSDNode.localName(child) == "element" else { continue }
            limited(PureXML.Schema.XSDNode.attribute(child, "maxOccurs"), allowZero: true, what: "the maxOccurs of a particle in an all group")
        }
        return errors
    }

    /// cos-all-limited: a reference to a model group whose content is an `all` group
    /// is itself an all-group particle, so its `maxOccurs` must be 1 and its
    /// `minOccurs` 0 or 1. ``allGroupLimitedErrors`` covers the direct `<all>` element;
    /// this covers a `<group ref>` resolving to an all group (corpus particlesEa025).
    static func allGroupReferenceMaxOccursErrors(_ schema: XSDTree) -> [String] {
        let xsd = PureXML.Schema.XSDParser.xsdNamespace
        var allGroupNames: Set<String> = []
        for group in descendants(schema, named: "group") where group.name?.namespaceURI == xsd {
            guard let name = PureXML.Schema.XSDNode.attribute(group, "name") else { continue }
            let isAll = PureXML.Schema.XSDNode.elementChildren(group).contains {
                $0.name?.namespaceURI == xsd && PureXML.Schema.XSDNode.localName($0) == "all"
            }
            if isAll { allGroupNames.insert(name) }
        }
        guard !allGroupNames.isEmpty else { return [] }
        var errors: [String] = []
        for group in descendants(schema, named: "group") where group.name?.namespaceURI == xsd {
            guard let ref = PureXML.Schema.XSDNode.attribute(group, "ref"),
                  allGroupNames.contains(PureXML.Schema.XSDNode.stripPrefix(ref))
            else { continue }
            let maxOccurs = PureXML.Schema.XSDNode.attribute(group, "maxOccurs")?.trimmingXMLWhitespace()
            if let maxOccurs, maxOccurs == "unbounded" || (isNonNegativeInteger(maxOccurs) && canonicalMagnitude(maxOccurs) != "1") {
                errors.append("the maxOccurs of a reference to an all group must be 1")
            }
            let minOccurs = PureXML.Schema.XSDNode.attribute(group, "minOccurs")?.trimmingXMLWhitespace()
            if let minOccurs, isNonNegativeInteger(minOccurs), !["0", "1"].contains(canonicalMagnitude(minOccurs)) {
                errors.append("the minOccurs of a reference to an all group must be 0 or 1")
            }
        }
        return errors
    }

    static func exceeds(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalMagnitude(lhs), right = canonicalMagnitude(rhs)
        return left.count != right.count ? left.count > right.count : left > right
    }

    static func canonicalMagnitude(_ value: String) -> Substring {
        var digits = Substring(value)
        if digits.first == "+" { digits = digits.dropFirst() }
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : trimmed
    }

    static func restrictionErrors(_ node: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        guard let parent = node.parent, parent.name?.namespaceURI == xsdNamespace, PureXML.Schema.XSDNode.localName(parent) == "simpleType" else { return [] }
        let simpleTypesCount = names.count { $0 == "simpleType" }
        if simpleTypesCount > 1 {
            errors.append("restriction under simpleType may have at most one inline simpleType")
        }
        var seenFacet = false
        for name in names {
            if name == "annotation" { continue }
            if name == "simpleType" {
                if seenFacet {
                    errors.append("inline simpleType must appear before facets in restriction")
                }
            } else if simpleTypeRestrictionAllowedChildren.contains(name) {
                seenFacet = true
            }
        }
        let hasBase = PureXML.Schema.XSDNode.attribute(node, "base") != nil
        let hasSimpleType = names.contains("simpleType")
        if hasBase, hasSimpleType {
            errors.append("restriction under simpleType cannot have both a 'base' attribute and an inline 'simpleType' child")
        }
        return errors
    }

    static func listErrors(_ node: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        let simpleTypes = names.count { $0 == "simpleType" }
        if simpleTypes > 1 {
            errors.append("list may have at most one inline simpleType")
        }
        let hasItemType = PureXML.Schema.XSDNode.attribute(node, "itemType") != nil
        let hasSimpleType = names.contains("simpleType")
        if hasItemType, hasSimpleType {
            errors.append("list cannot have both an 'itemType' attribute and an inline 'simpleType' child")
        }
        return errors
    }

    static func schemaChildrenOrderErrors(_ names: [String]) -> [String] {
        var errors: [String] = []
        var seenDeclaration = false
        for name in names {
            if ["simpleType", "complexType", "group", "attributeGroup", "element", "attribute", "notation"].contains(name) {
                seenDeclaration = true
            } else if ["include", "import", "redefine"].contains(name) {
                if seenDeclaration {
                    errors.append("schema element '\(name)' must appear before any global declarations")
                }
            }
        }
        return errors
    }

    static func importErrors(_ node: XSDTree) -> [String] {
        var errors: [String] = []
        let namespaceAttr = node.attributes.first { $0.name.prefix == nil && $0.name.localName == "namespace" }?.value
        var current: XSDTree? = node.parent
        var schemaNode: XSDTree?
        while let ancestor = current {
            if ancestor.name?.namespaceURI == xsdNamespace, PureXML.Schema.XSDNode.localName(ancestor) == "schema" {
                schemaNode = ancestor
                break
            }
            current = ancestor.parent
        }
        if let schemaNode {
            let targetNamespace = schemaNode.attributes.first { $0.name.prefix == nil && $0.name.localName == "targetNamespace" }?.value
            if namespaceAttr == nil {
                if targetNamespace == nil {
                    errors.append("import element without namespace attribute requires targetNamespace on the schema element")
                }
            } else if let namespaceAttr, namespaceAttr == targetNamespace {
                errors.append("import element's namespace attribute must not be the same as the targetNamespace of the importing schema")
            }
        }
        return errors
    }

    static func elementChildrenErrors(_: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        let simpleTypes = names.count { $0 == "simpleType" }
        let complexTypes = names.count { $0 == "complexType" }
        if (simpleTypes + complexTypes) > 1 {
            errors.append("element may have at most one inline type definition (simpleType or complexType)")
        }
        var seenIdentityConstraint = false
        for name in names {
            if name == "annotation" { continue }
            if name == "simpleType" || name == "complexType" {
                if seenIdentityConstraint {
                    errors.append("inline type definition must appear before identity constraints in element")
                }
            } else if ["unique", "key", "keyref"].contains(name) {
                seenIdentityConstraint = true
            }
        }
        return errors
    }

    static func attributeChildrenErrors(_: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        let simpleTypes = names.count { $0 == "simpleType" }
        if simpleTypes > 1 {
            errors.append("attribute may have at most one inline simpleType")
        }
        return errors
    }

    static func attributeGroupChildrenErrors(_ node: XSDTree, names: [String]) -> [String] {
        // A referencing attributeGroup (one with `ref`) names a definition elsewhere;
        // its own content model is (annotation?), so it may not also declare
        // attributes, nested attributeGroup references, or an anyAttribute. Only a
        // defining attributeGroup (with `name`) carries those.
        if PureXML.Schema.XSDNode.attribute(node, "ref") != nil {
            return names.contains { $0 != "annotation" }
                ? ["an attributeGroup reference may contain only an optional annotation"]
                : []
        }
        var errors: [String] = []
        let anyAttributes = names.count { $0 == "anyAttribute" }
        if anyAttributes > 1 {
            errors.append("attributeGroup may have at most one anyAttribute")
        }
        var seenAnyAttribute = false
        for name in names {
            if name == "annotation" { continue }
            if name == "attribute" || name == "attributeGroup" {
                if seenAnyAttribute {
                    errors.append("attribute and attributeGroup references must appear before anyAttribute in attributeGroup")
                }
            } else if name == "anyAttribute" {
                seenAnyAttribute = true
            }
        }
        return errors
    }

    /// A `complexType` nested in an `element` is a local (anonymous) type and must
    /// not carry a `name`; only a top-level `complexType` (a child of `schema`, or a
    /// `redefine` redefinition) is named. A local type definition has no name.
    static func localComplexTypeNameErrors(_ node: XSDTree) -> [String] {
        guard PureXML.Schema.XSDNode.attribute(node, "name") != nil,
              let parent = node.parent,
              parent.name?.namespaceURI == xsdNamespace,
              PureXML.Schema.XSDNode.localName(parent) == "element"
        else { return [] }
        return ["a complexType nested in an element must not have a 'name' attribute"]
    }

    /// The content model of an identity constraint (`unique`/`key`/`keyref`) is
    /// `(annotation?, selector, field+)`: exactly one `selector`, then one or more
    /// `field`s, in that order. A `field` before the `selector`, a second
    /// `selector`, or no `field` is invalid. (`names` is already the XSD-namespace
    /// children; misplaced annotation is checked by the general annotation rule.)
    static func identityConstraintContentErrors(_ names: [String]) -> [String] {
        let meaningful = names.filter { $0 != "annotation" }
        let wellFormed = meaningful.first == "selector"
            && meaningful.count >= 2
            && meaningful.dropFirst().allSatisfy { $0 == "field" }
        return wellFormed ? [] : ["an identity constraint must contain one selector followed by one or more fields"]
    }

    static func groupChildrenErrors(_: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        let compositors = names.count { $0 == "all" || $0 == "choice" || $0 == "sequence" }
        if compositors > 1 {
            errors.append("group may have at most one compositor (all, choice, or sequence)")
        }
        return errors
    }

    /// The finding, if any, for occurrence on a named group's compositor: the
    /// `all`/`choice`/`sequence` directly inside a top-level `xs:group` definition
    /// must not carry `minOccurs`/`maxOccurs` (those belong on a group reference).
    static func namedGroupOccurrenceErrors(_ group: XSDTree) -> [String] {
        let xsd = PureXML.Schema.XSDParser.xsdNamespace
        for child in PureXML.Schema.XSDNode.elementChildren(group) where child.name?.namespaceURI == xsd {
            guard let local = PureXML.Schema.XSDNode.localName(child),
                  local == "all" || local == "choice" || local == "sequence"
            else { continue }
            let hasOccurrence = PureXML.Schema.XSDNode.attribute(child, "minOccurs") != nil
                || PureXML.Schema.XSDNode.attribute(child, "maxOccurs") != nil
            if hasOccurrence {
                return ["the compositor in a named group must not specify minOccurs or maxOccurs"]
            }
        }
        return []
    }

    /// A namespace value must be a non-empty `anyURI` (or absent): the empty string
    /// is not a legal namespace name. So `<schema targetNamespace="">` and
    /// `<import namespace="">` are invalid, while omitting the attribute (no target
    /// namespace, a no-namespace import) stays valid.
    static func emptyNamespaceErrors(_ schema: XSDTree) -> [String] {
        var errors: [String] = []
        if PureXML.Schema.XSDNode.attribute(schema, "targetNamespace") == "" {
            errors.append("the 'targetNamespace' attribute may not be the empty string")
        }
        for importNode in descendants(schema, named: "import") where PureXML.Schema.XSDNode.attribute(importNode, "namespace") == "" {
            errors.append("an 'import' namespace may not be the empty string")
        }
        return errors
    }
}
