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

    /// Simple types for identity-constraint field paths, keyed by
    /// ``identityFieldKey(constraint:field:)``.
    static func identityFieldTypes(_ containers: [XSDTree], _ context: PureXML.Schema.XSDContext) -> [String: PureXML.Schema.SimpleType] {
        var types: [String: PureXML.Schema.SimpleType] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                let constraints = PureXML.Schema.XSDNode.elementChildren(element).compactMap(constraint)
                guard !constraints.isEmpty else { continue }
                for constraint in constraints {
                    for field in constraint.fields {
                        if field == ".", selectorBranches(constraint.selector).count > 1 {
                            for branch in selectorBranches(constraint.selector) {
                                if let type = declaredElementSimpleType(named: branch, under: element, context) {
                                    types[identityFieldKey(constraint: constraint, field: field, targetLocal: branch)] = type
                                }
                            }
                            continue
                        }
                        if let type = identityFieldType(field, host: element, constraint: constraint, containers: containers, context) {
                            types[identityFieldKey(constraint: constraint, field: field)] = type
                        }
                    }
                }
            }
        }
        return types
    }

    /// The `default`/`fixed` value constraints declared on identity-constraint
    /// field targets, keyed by ``identityFieldKey(constraint:field:)``. Mirrors
    /// ``identityFieldTypes(_:_:)``'s traversal and keying: for an `@attr` field
    /// the matched attribute use's value constraint, for a `.` field the
    /// selector-target element's own `default`/`fixed`. Only fields whose target
    /// declares a default or fixed value appear, so an absent attribute or empty
    /// element takes that value as its identity tuple component (idG011/idG012,
    /// idF016/idF017).
    static func identityFieldConstraints(_ containers: [XSDTree], _ context: PureXML.Schema.XSDContext) -> [String: PureXML.Schema.ValueConstraint] {
        var constraints: [String: PureXML.Schema.ValueConstraint] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                let declared = PureXML.Schema.XSDNode.elementChildren(element).compactMap(constraint)
                guard !declared.isEmpty else { continue }
                for constraint in declared {
                    for field in constraint.fields {
                        if field == ".", selectorBranches(constraint.selector).count > 1 {
                            for branch in selectorBranches(constraint.selector) {
                                if let value = declaredElementValueConstraint(named: branch, under: element, containers) {
                                    constraints[identityFieldKey(constraint: constraint, field: field, targetLocal: branch)] = value
                                }
                            }
                            continue
                        }
                        if let value = identityFieldValueConstraint(field, host: element, constraint: constraint, containers: containers, context) {
                            constraints[identityFieldKey(constraint: constraint, field: field)] = value
                        }
                    }
                }
            }
        }
        return constraints
    }

    private static func identityFieldValueConstraint(
        _ field: String,
        host: XSDTree,
        constraint: PureXML.Schema.IdentityConstraint,
        containers: [XSDTree],
        _ context: PureXML.Schema.XSDContext,
    ) -> PureXML.Schema.ValueConstraint? {
        if field.hasPrefix("@") {
            let attributeName = identityFieldAttributeName(field)
            return attributeValueConstraint(named: attributeName, host: host, constraint: constraint, containers: containers, context)
        }
        if field == "." {
            return declaredElementValueConstraint(named: selectorTargetLocalName(constraint.selector), under: host, containers)
        }
        return nil
    }

    /// The value constraint of the attribute an `@attr` field names: the use under
    /// the host first, else (when the selector targets a referenced global element)
    /// the use on that element's own complex type. Mirrors
    /// ``identityFieldType(_:host:constraint:containers:_:)``'s attribute search.
    private static func attributeValueConstraint(
        named attributeName: String,
        host: XSDTree,
        constraint: PureXML.Schema.IdentityConstraint,
        containers: [XSDTree],
        _ context: PureXML.Schema.XSDContext,
    ) -> PureXML.Schema.ValueConstraint? {
        for element in descendants(host, named: "element") {
            guard let complex = PureXML.Schema.XSDNode.firstChild(element, named: "complexType") else { continue }
            for attribute in descendants(complex, named: "attribute") where PureXML.Schema.XSDNode.attribute(attribute, "name") == attributeName {
                if let use = PureXML.Schema.XSDParser.attributeUse(attribute, context), let value = use.valueConstraint { return value }
            }
        }
        guard let target = selectorTargetLocalName(constraint.selector),
              let element = globalElementNode(named: target, containers),
              let complex = PureXML.Schema.XSDNode.firstChild(element, named: "complexType")
        else { return nil }
        for attribute in descendants(complex, named: "attribute") where PureXML.Schema.XSDNode.attribute(attribute, "name") == attributeName {
            if let use = PureXML.Schema.XSDParser.attributeUse(attribute, context), let value = use.valueConstraint { return value }
        }
        return nil
    }

    /// The `default`/`fixed` of the selector-target element a `.` field denotes:
    /// the global element of that local name (the selector targets a referenced
    /// global), else the locally declared element of that name under the host.
    private static func declaredElementValueConstraint(named local: String?, under host: XSDTree, _ containers: [XSDTree]) -> PureXML.Schema.ValueConstraint? {
        guard let local else { return valueConstraint(of: host) }
        if let element = globalElementNode(named: local, containers), let value = valueConstraint(of: element) {
            return value
        }
        guard let complex = PureXML.Schema.XSDNode.firstChild(host, named: "complexType") else { return nil }
        for child in descendants(complex, named: "element") where PureXML.Schema.XSDNode.attribute(child, "name") == local {
            if let value = valueConstraint(of: child) { return value }
        }
        return nil
    }

    static func identityFieldKey(constraint: PureXML.Schema.IdentityConstraint, field: String, targetLocal: String? = nil) -> String {
        if let targetLocal { return "\(constraint.name)|\(field)|\(targetLocal)" }
        return "\(constraint.name)|\(field)"
    }

    private static func selectorBranches(_ selector: String) -> [String] {
        let token = selector.split(separator: "/").last.map(String.init) ?? selector
        guard token.contains("|") else {
            return selectorTargetLocalName(selector).map { [$0] } ?? []
        }
        return token.split(separator: "|").compactMap { branch in
            let local = PureXML.Schema.XSDNode.stripPrefix(String(branch))
            return local.isEmpty ? nil : local
        }
    }

    private static func identityFieldType(
        _ field: String,
        host: XSDTree,
        constraint: PureXML.Schema.IdentityConstraint,
        containers: [XSDTree],
        _ context: PureXML.Schema.XSDContext,
    ) -> PureXML.Schema.SimpleType? {
        if field.hasPrefix("@") {
            let attributeName = identityFieldAttributeName(field)
            if let type = attributeType(named: attributeName, under: host, context) { return type }
            // The selector's target may be a global element referenced from the
            // host rather than nested under it; the attribute is then on that
            // element's own complex type, so field values compare in its value
            // space (e.g. 3.0 and 3 are the same xsd:decimal key).
            guard let target = selectorTargetLocalName(constraint.selector),
                  let element = globalElementNode(named: target, containers),
                  let complex = PureXML.Schema.XSDNode.firstChild(element, named: "complexType")
            else { return nil }
            for attribute in descendants(complex, named: "attribute") {
                guard PureXML.Schema.XSDNode.attribute(attribute, "name") == attributeName else { continue }
                if let use = PureXML.Schema.XSDParser.attributeUse(attribute, context) { return use.type }
            }
            return nil
        }
        if field == "." {
            let local = selectorTargetLocalName(constraint.selector)
            return declaredElementSimpleType(named: local, under: host, context)
        }
        return nil
    }

    private static func identityFieldAttributeName(_ field: String) -> String {
        let token = field.split(separator: "|").first.map(String.init) ?? field
        guard token.hasPrefix("@") else { return String(field.dropFirst()) }
        return String(token.dropFirst())
    }

    private static func selectorTargetLocalName(_ selector: String) -> String? {
        let token = selector.split(separator: "/").last.map(String.init) ?? selector
        return PureXML.Schema.XSDNode.stripPrefix(token)
    }

    /// The top-level (global) element declaration node of the given local name.
    private static func globalElementNode(named local: String, _ containers: [XSDTree]) -> XSDTree? {
        for container in containers {
            for child in PureXML.Schema.XSDNode.elementChildren(container) {
                guard PureXML.Schema.XSDNode.localName(child) == "element",
                      PureXML.Schema.XSDNode.attribute(child, "name") == local
                else { continue }
                return child
            }
        }
        return nil
    }

    private static func declaredElementSimpleType(
        named local: String?,
        under host: XSDTree,
        _ context: PureXML.Schema.XSDContext,
    ) -> PureXML.Schema.SimpleType? {
        guard let local else { return elementSimpleType(under: host, context) }
        guard let complex = PureXML.Schema.XSDNode.firstChild(host, named: "complexType") else { return nil }
        for child in descendants(complex, named: "element") {
            guard PureXML.Schema.XSDNode.attribute(child, "name") == local,
                  let typeName = PureXML.Schema.XSDNode.attribute(child, "type")
            else { continue }
            let stripped = PureXML.Schema.XSDNode.stripPrefix(typeName)
            let uri = PureXML.Schema.XSDNode.referenceNamespace(typeName, context.namespaceBindings)
            if uri == PureXML.Schema.XSDParser.xsdNamespace, let builtin = PureXML.Schema.BuiltinType(rawValue: stripped) {
                return PureXML.Schema.SimpleType(base: builtin)
            }
        }
        return nil
    }

    private static func attributeType(named name: String, under host: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType? {
        for element in descendants(host, named: "element") {
            guard let complex = PureXML.Schema.XSDNode.firstChild(element, named: "complexType") else { continue }
            for attribute in descendants(complex, named: "attribute") {
                guard PureXML.Schema.XSDNode.attribute(attribute, "name") == name else { continue }
                if let use = PureXML.Schema.XSDParser.attributeUse(attribute, context) {
                    return use.type
                }
            }
        }
        return nil
    }

    private static func elementSimpleType(under host: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType? {
        guard let complex = PureXML.Schema.XSDNode.firstChild(host, named: "complexType") else { return nil }
        for child in descendants(complex, named: "element") {
            guard let typeName = PureXML.Schema.XSDNode.attribute(child, "type") else { continue }
            let local = PureXML.Schema.XSDNode.stripPrefix(typeName)
            let uri = PureXML.Schema.XSDNode.referenceNamespace(typeName, context.namespaceBindings)
            if uri == PureXML.Schema.XSDParser.xsdNamespace, let builtin = PureXML.Schema.BuiltinType(rawValue: local) {
                return PureXML.Schema.SimpleType(base: builtin)
            }
        }
        return nil
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
        return PureXML.Schema.IdentityConstraint(
            name: PureXML.Schema.XSDNode.attribute(node, "name") ?? "",
            kind: kind,
            selector: selector,
            fields: fields,
            namespaceBindings: PureXML.Schema.XSDParser.namespaceBindingsInScope(of: node, defaultBindings: [:]),
        )
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

    /// Splits a namespaced identity key (`{ns}local`, as produced by
    /// ``ComplexValidator/key(_:)``) into its local name and namespace. An empty
    /// namespace segment is reported as nil (no namespace). A key with no namespace
    /// braces is treated as a bare local name in no namespace.
    static func unpackElementName(_ key: String) -> (String, String?) {
        guard key.hasPrefix("{"), let close = key.firstIndex(of: "}") else { return (key, nil) }
        let uri = String(key[key.index(after: key.startIndex) ..< close])
        let local = String(key[key.index(after: close)...])
        return (local, uri.isEmpty ? nil : uri)
    }

    /// The local name from a type-table key (`type:{namespace}local` or a legacy bare name).
    static func bareTypeLocalName(_ reference: String) -> String {
        guard reference.hasPrefix("type:") else { return reference }
        let key = String(reference.dropFirst("type:".count))
        guard let close = key.firstIndex(of: "}") else { return key }
        return String(key[key.index(after: close)...])
    }

    /// The type-table key for a global type declaration in a specific namespace.
    static func typeDeclarationKey(_ localName: String, namespaceURI: String?) -> String {
        "type:\(PureXML.Schema.ComplexValidator.key(PureXML.Model.QualifiedName(localName: localName, namespaceURI: namespaceURI)))"
    }

    /// The type-table key for a global element declaration in a specific namespace.
    static func elementDeclarationKey(_ name: PureXML.Model.QualifiedName) -> String {
        "element:\(PureXML.Schema.ComplexValidator.key(name))"
    }

    /// The lookup key for a global attribute declaration in a specific namespace.
    static func attributeDeclarationKey(_ name: PureXML.Model.QualifiedName) -> String {
        "attribute:\(PureXML.Schema.ComplexValidator.key(name))"
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
