private typealias XSDDerivNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// Gathers the derivation-control facts (``DerivationTables``) from a schema's
    /// definition containers, building both the bare-keyed tables (for the
    /// schema-consistency machinery) and the namespaced (`{ns}local`) tables (for
    /// the instance-validity subsystem) in one pass, resolving each container's
    /// components through its target namespace and prefix bindings.
    static func derivationTables(_ containers: [XSDTree], mainTargetNamespace: String?) -> DerivationTables {
        var tables = DerivationTables()
        let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: mainTargetNamespace)
        for index in containers.indices {
            let container = containers[index]
            let containerNamespace = namespaceMap[index] ?? mainTargetNamespace
            for type in descendants(container, named: "complexType") {
                gatherType(type, in: containerNamespace, into: &tables)
            }
            for type in descendants(container, named: "simpleType") {
                gatherSimpleType(type, in: containerNamespace, into: &tables)
            }
            for element in descendants(container, named: "element") {
                gatherElement(element, in: containerNamespace, into: &tables)
            }
        }
        return tables
    }

    /// The namespaced derivation-table key (`{ns}local`) for a component named
    /// `local` in `namespace`, matching ``ComplexValidator/key(_:)``.
    static func derivationKey(_ local: String, in namespace: String?) -> String {
        PureXML.Schema.ComplexValidator.key(PureXML.Model.QualifiedName(localName: local, namespaceURI: namespace))
    }

    /// The namespaced key a base/type QName resolves to, given `node`'s in-scope
    /// prefix bindings. A prefixed QName uses its prefix's binding; an unprefixed
    /// QName the default-namespace binding when declared, else the component's own
    /// target namespace.
    private static func resolvedKey(of qualified: String, on node: XSDTree, default containerNamespace: String?) -> String {
        let bindings = namespaceBindingsInScope(of: node, defaultBindings: [:])
        let resolved = XSDDerivNode.prefix(qualified) != nil
            ? XSDDerivNode.referenceNamespace(qualified, bindings)
            : (bindings[""] ?? containerNamespace)
        return derivationKey(XSDDerivNode.stripPrefix(qualified), in: resolved)
    }

    /// Records a named `simpleType`'s restriction derivation and `final` controls.
    /// A `simpleType` derives from its `restriction`'s `base`; a `list`/`union`
    /// constructs a new type (deriving from `anySimpleType`), so it is left
    /// unrecorded, which keeps two independent list/union types correctly
    /// non-derivable from one another.
    private static func gatherSimpleType(_ type: XSDTree, in namespace: String?, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        let finalSet = methodSet(XSDDerivNode.attribute(type, "final"))
        if !finalSet.isEmpty { tables.typeFinal[name] = finalSet }
        // A union's named member types: record them so the xsi:type-block check
        // can follow a derivation that reaches this union through a member
        // (cos-st-derived-OK 2.2.4). Inline (anonymous) members carry no name to
        // record and are left out, which keeps the check silent rather than risk
        // a false positive.
        let union = XSDDerivNode.firstChild(type, named: "union")
        if let union, let members = XSDDerivNode.attribute(union, "memberTypes") {
            let memberKeys = members.split(whereSeparator: \.isWhitespace).map {
                resolvedKey(of: String($0), on: union, default: namespace)
            }
            if !memberKeys.isEmpty { tables.nsUnionMembers[derivationKey(name, in: namespace)] = memberKeys }
        }
        guard let restriction = XSDDerivNode.firstChild(type, named: "restriction"),
              let base = XSDDerivNode.attribute(restriction, "base") else { return }
        tables.typeDerivation[name] = PureXML.Schema.TypeDerivation(base: XSDDerivNode.stripPrefix(base), method: .restriction)
        tables.nsTypeDerivation[derivationKey(name, in: namespace)] = PureXML.Schema.TypeDerivation(
            base: resolvedKey(of: base, on: type, default: namespace),
            method: .restriction,
        )
    }

    private static func gatherType(_ type: XSDTree, in namespace: String?, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        let key = derivationKey(name, in: namespace)
        if XSDDerivNode.attribute(type, "abstract") == "true" {
            tables.abstractTypes.insert(name)
            tables.nsAbstractTypes.insert(key)
        }
        let block = blockMethods(of: type, admitting: [.extension, .restriction])
        if !block.isEmpty {
            tables.typeBlock[name] = block
            tables.nsTypeBlock[key] = block
        }
        let finalSet = finalMethods(of: type)
        if !finalSet.isEmpty { tables.typeFinal[name] = finalSet }
        if let derivation = derivationInfo(type) { tables.typeDerivation[name] = derivation }
        if let derivation = namespacedDerivationInfo(type, in: namespace) { tables.nsTypeDerivation[key] = derivation }
    }

    private static func gatherElement(_ element: XSDTree, in namespace: String?, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(element, "name") else { return }
        let isGlobal = element.parent.map {
            $0.name?.namespaceURI == xsdNamespace && XSDDerivNode.localName($0) == "schema"
        } ?? false
        // A global element is always in the target namespace; a local element is in
        // it only when qualified (its `form`, else the schema's elementFormDefault),
        // so its namespaced key matches the instance element's qualified name.
        let elementNamespace = isGlobal ? namespace : localElementNamespace(element, in: namespace)
        let key = derivationKey(name, in: elementNamespace)
        if XSDDerivNode.attribute(element, "abstract") == "true" { tables.abstractElements.insert(name) }
        let block = blockMethods(of: element, admitting: [.extension, .restriction, .substitution])
        if !block.isEmpty {
            tables.elementBlock[name] = block
            tables.nsElementBlock[key] = block
        }
        if isGlobal {
            let finalSet = finalMethods(of: element)
            if !finalSet.isEmpty { tables.elementFinal[name] = finalSet }
        }
        if let type = XSDDerivNode.attribute(element, "type") {
            tables.elementTypeNames[name] = XSDDerivNode.stripPrefix(type)
            tables.nsElementTypeNames[key] = resolvedKey(of: type, on: element, default: namespace)
        } else {
            recordInlineElementDerivation(element, key: key, in: namespace, into: &tables)
        }
    }

    /// Records the derivation of an element's INLINE complex type, which carries no
    /// `type` name and so is absent from the named backbone. The entry is keyed by a
    /// synthetic key (the element key plus a `#` marker no QName can contain, so it
    /// cannot collide with a real type and is unreachable as anyone else's derivation
    /// base) so a substitution-group `block` on the head can drop a member whose inline
    /// type reaches the head's type by a blocked method (cos-equiv-derived-ok-rec; XSTS
    /// disallowedSubst00105m). A plain inline type with no derivation records nothing.
    private static func recordInlineElementDerivation(_ element: XSDTree, key: String, in namespace: String?, into tables: inout DerivationTables) {
        guard let inlineType = XSDDerivNode.firstChild(element, named: "complexType"),
              let derivation = namespacedDerivationInfo(inlineType, in: namespace)
        else { return }
        let inlineKey = key + "#inline"
        tables.nsElementTypeNames[key] = inlineKey
        tables.nsTypeDerivation[inlineKey] = derivation
    }

    /// The namespace a local element's name takes at instance level: the target
    /// namespace when the element is qualified (its own `form`, else the schema's
    /// `elementFormDefault`), otherwise no namespace.
    private static func localElementNamespace(_ element: XSDTree, in namespace: String?) -> String? {
        switch XSDDerivNode.attribute(element, "form") {
        case "qualified": return namespace
        case "unqualified": return nil
        default:
            let schema = XSDDerivNode.schemaOwner(element)
            return XSDDerivNode.attribute(schema, "elementFormDefault") == "qualified" ? namespace : nil
        }
    }

    /// The namespaced (`{ns}local`-based) derivation backbone of a complex type:
    /// the same `complexContent`/`simpleContent` extension/restriction base as
    /// ``derivationInfo(_:)``, but with the base resolved to a namespaced key.
    private static func namespacedDerivationInfo(_ type: XSDTree, in namespace: String?) -> PureXML.Schema.TypeDerivation? {
        let container = XSDDerivNode.firstChild(type, named: "complexContent")
            ?? XSDDerivNode.firstChild(type, named: "simpleContent")
        guard let container else { return nil }
        if let ext = XSDDerivNode.firstChild(container, named: "extension"), let base = XSDDerivNode.attribute(ext, "base") {
            return PureXML.Schema.TypeDerivation(base: resolvedKey(of: base, on: type, default: namespace), method: .extension)
        }
        if let res = XSDDerivNode.firstChild(container, named: "restriction"), let base = XSDDerivNode.attribute(res, "base") {
            return PureXML.Schema.TypeDerivation(base: resolvedKey(of: base, on: type, default: namespace), method: .restriction)
        }
        return nil
    }
}
