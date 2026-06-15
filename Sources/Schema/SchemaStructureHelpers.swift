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

    static func occurrenceOrderErrors(_ node: XSDTree) -> [String] {
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

    static func attributeGroupChildrenErrors(_: XSDTree, names: [String]) -> [String] {
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

    static func groupChildrenErrors(_: XSDTree, names: [String]) -> [String] {
        var errors: [String] = []
        let compositors = names.count { $0 == "all" || $0 == "choice" || $0 == "sequence" }
        if compositors > 1 {
            errors.append("group may have at most one compositor (all, choice, or sequence)")
        }
        return errors
    }
}
