extension PureXML.Schema.XSDParser {
    /// Gathers `nillable` and `default`/`fixed` value constraints from every
    /// element declaration at any depth, keyed by the element's name.
    static func elementMetadata(_ containers: [XSDTree]) -> (Set<String>, [String: PureXML.Schema.ValueConstraint]) {
        var nillable: Set<String> = []
        var constraints: [String: PureXML.Schema.ValueConstraint] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                guard let name = PureXML.Schema.XSDNode.attribute(element, "name") else { continue }
                if PureXML.Schema.XSDNode.attribute(element, "nillable") == "true" { nillable.insert(name) }
                if let constraint = valueConstraint(of: element) { constraints[name] = constraint }
            }
        }
        return (nillable, constraints)
    }

    /// Gathers identity constraints (`unique`, `key`, `keyref`) declared on any
    /// element at any depth, keyed by the element's name.
    static func identityConstraints(_ containers: [XSDTree]) -> [String: [PureXML.Schema.IdentityConstraint]] {
        var map: [String: [PureXML.Schema.IdentityConstraint]] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                guard let name = PureXML.Schema.XSDNode.attribute(element, "name") else { continue }
                let constraints = PureXML.Schema.XSDNode.elementChildren(element).compactMap(constraint)
                if !constraints.isEmpty { map[name, default: []] += constraints }
            }
        }
        return map
    }

    private static func constraint(_ node: XSDTree) -> PureXML.Schema.IdentityConstraint? {
        let kind: PureXML.Schema.IdentityConstraintKind
        switch PureXML.Schema.XSDNode.localName(node) {
        case "unique": kind = .unique
        case "key": kind = .key
        case "keyref": kind = .keyref(refer: PureXML.Schema.XSDNode.stripPrefix(PureXML.Schema.XSDNode.attribute(node, "refer") ?? ""))
        default: return nil
        }
        let selector = PureXML.Schema.XSDNode.firstChild(node, named: "selector").flatMap { PureXML.Schema.XSDNode.attribute($0, "xpath") } ?? ""
        let fields = PureXML.Schema.XSDNode.children(node, named: "field").compactMap { PureXML.Schema.XSDNode.attribute($0, "xpath") }
        return PureXML.Schema.IdentityConstraint(name: PureXML.Schema.XSDNode.attribute(node, "name") ?? "", kind: kind, selector: selector, fields: fields)
    }

    static func descendants(_ node: XSDTree, named name: String) -> [XSDTree] {
        var result: [XSDTree] = []
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            if PureXML.Schema.XSDNode.localName(child) == name { result.append(child) }
            result += descendants(child, named: name)
        }
        return result
    }

    /// The qualified name of a local element declaration: in the target namespace
    /// when `elementFormDefault` (or the element's own `form`) is qualified,
    /// otherwise in no namespace.
    static func localElementName(_ name: String, _ form: String?, _ context: PureXML.Schema.XSDContext) -> PureXML.Model.QualifiedName {
        let qualified = form == "qualified" || (form == nil && context.elementFormQualified)
        return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
    }

    static func elementKey(_ name: String) -> String {
        "element:\(name)"
    }

    static func indexByName(_ nodes: [XSDTree]) -> [String: XSDTree] {
        var index: [String: XSDTree] = [:]
        for node in nodes {
            if let name = PureXML.Schema.XSDNode.attribute(node, "name") { index[name] = node }
        }
        return index
    }

    static func elementTypeName(_ node: XSDTree) -> String? {
        if let typeName = PureXML.Schema.XSDNode.attribute(node, "type") {
            return PureXML.Schema.XSDNode.stripPrefix(typeName)
        }
        if PureXML.Schema.XSDNode.firstChild(node, named: "simpleType") != nil || PureXML.Schema.XSDNode.firstChild(node, named: "complexType") != nil {
            return nil
        }
        return "anyType"
    }

    static func derivation(_ node: XSDTree) -> XSDTree? {
        PureXML.Schema.XSDNode.firstChild(node, named: "restriction") ?? PureXML.Schema.XSDNode.firstChild(node, named: "extension")
    }

    static func valueConstraint(of node: XSDTree) -> PureXML.Schema.ValueConstraint? {
        if let fixed = PureXML.Schema.XSDNode.attribute(node, "fixed") { return .fixed(fixed) }
        if let value = PureXML.Schema.XSDNode.attribute(node, "default") { return .default(value) }
        return nil
    }
}
