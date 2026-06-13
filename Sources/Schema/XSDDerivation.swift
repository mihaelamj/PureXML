private typealias SchemaFault = PureXML.Schema.SchemaError
private typealias XSDDerivNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// The derivation-control facts gathered from a schema's definition
    /// containers: which types and elements are abstract, the `block`/`final`
    /// derivation methods each names, every named complex type's base and
    /// derivation method, and each element's declared type name (needed to test a
    /// substitution member's derivation against its head's `block`).
    ///
    /// Note: this records the derivation *backbone* (base + method) and enforces
    /// `block`, `final`, and abstract usage. The structural subset check for a
    /// complex-type restriction ("Particle Valid (Restriction)" in XSD 1.0) runs
    /// separately at schema compile, see ``ParticleRestriction``.
    struct DerivationTables {
        var typeDerivation: [String: PureXML.Schema.TypeDerivation] = [:]
        var abstractTypes: Set<String> = []
        var typeBlock: [String: Set<PureXML.Schema.DerivationMethod>] = [:]
        var typeFinal: [String: Set<PureXML.Schema.DerivationMethod>] = [:]
        var abstractElements: Set<String> = []
        var elementBlock: [String: Set<PureXML.Schema.DerivationMethod>] = [:]
        var elementTypeNames: [String: String] = [:]
    }

    static func derivationTables(_ containers: [XSDTree]) -> DerivationTables {
        var tables = DerivationTables()
        for container in containers {
            for type in descendants(container, named: "complexType") {
                gatherType(type, into: &tables)
            }
            for element in descendants(container, named: "element") {
                gatherElement(element, into: &tables)
            }
        }
        return tables
    }

    private static func gatherType(_ type: XSDTree, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        if XSDDerivNode.attribute(type, "abstract") == "true" { tables.abstractTypes.insert(name) }
        let block = methodSet(XSDDerivNode.attribute(type, "block"))
        if !block.isEmpty { tables.typeBlock[name] = block }
        let finalSet = methodSet(XSDDerivNode.attribute(type, "final"))
        if !finalSet.isEmpty { tables.typeFinal[name] = finalSet }
        if let derivation = derivationInfo(type) { tables.typeDerivation[name] = derivation }
    }

    private static func gatherElement(_ element: XSDTree, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(element, "name") else { return }
        if XSDDerivNode.attribute(element, "abstract") == "true" { tables.abstractElements.insert(name) }
        let block = methodSet(XSDDerivNode.attribute(element, "block"))
        if !block.isEmpty { tables.elementBlock[name] = block }
        if let type = XSDDerivNode.attribute(element, "type") {
            tables.elementTypeNames[name] = XSDDerivNode.stripPrefix(type)
        }
    }

    /// Parses a `block`/`final`/`substitutionGroup`-style value: `#all` for every
    /// method, or a whitespace-separated subset of `extension`/`restriction`/
    /// `substitution`.
    static func methodSet(_ raw: String?) -> Set<PureXML.Schema.DerivationMethod> {
        guard let raw, !raw.isEmpty else { return [] }
        var set: Set<PureXML.Schema.DerivationMethod> = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            switch token {
            case "#all": return [.extension, .restriction, .substitution]
            case "extension": set.insert(.extension)
            case "restriction": set.insert(.restriction)
            case "substitution": set.insert(.substitution)
            default: break
            }
        }
        return set
    }

    /// The base type and derivation method a named complex type declares through
    /// its `complexContent`/`simpleContent` `extension` or `restriction`.
    static func derivationInfo(_ type: XSDTree) -> PureXML.Schema.TypeDerivation? {
        let container = XSDDerivNode.firstChild(type, named: "complexContent")
            ?? XSDDerivNode.firstChild(type, named: "simpleContent")
        guard let container else { return nil }
        if let ext = XSDDerivNode.firstChild(container, named: "extension"), let base = XSDDerivNode.attribute(ext, "base") {
            return PureXML.Schema.TypeDerivation(base: XSDDerivNode.stripPrefix(base), method: .extension)
        }
        if let res = XSDDerivNode.firstChild(container, named: "restriction"), let base = XSDDerivNode.attribute(res, "base") {
            return PureXML.Schema.TypeDerivation(base: XSDDerivNode.stripPrefix(base), method: .restriction)
        }
        return nil
    }

    /// The derivation methods along the chain from `derived` up to `base`, or nil
    /// when `derived` does not derive from `base`. An empty set means they are the
    /// same type. Cycle-guarded so a malformed schema cannot loop.
    static func derivationMethods(from derived: String, to base: String, _ table: [String: PureXML.Schema.TypeDerivation]) -> Set<PureXML.Schema.DerivationMethod>? {
        var methods: Set<PureXML.Schema.DerivationMethod> = []
        var current = derived
        var visited: Set<String> = [derived]
        while current != base {
            guard let step = table[current] else { return nil }
            methods.insert(step.method)
            guard visited.insert(step.base).inserted else { return nil }
            current = step.base
        }
        return methods
    }

    /// Throws when a type inside an `xs:redefine` does not derive from itself: a
    /// redefinition's `base` must name the type being redefined.
    static func checkRedefine(_ containers: [XSDTree]) throws {
        for container in containers where XSDDerivNode.localName(container) == "redefine" {
            for type in XSDDerivNode.children(container, named: "complexType") {
                guard let name = XSDDerivNode.attribute(type, "name") else { continue }
                if derivationInfo(type)?.base != name { throw SchemaFault.redefineIncompatible(type: name) }
            }
            for type in XSDDerivNode.children(container, named: "simpleType") {
                try checkRedefinedSimpleType(type)
            }
        }
    }

    private static func checkRedefinedSimpleType(_ type: XSDTree) throws {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        let base = XSDDerivNode.firstChild(type, named: "restriction")
            .flatMap { XSDDerivNode.attribute($0, "base") }
            .map(XSDDerivNode.stripPrefix)
        if base != name { throw SchemaFault.redefineIncompatible(type: name) }
    }

    /// Drops from each substitution group the members a head's `block` forbids: a
    /// member whose type derives from the head's type by a blocked method may not
    /// substitute.
    static func filterSubstitutions(_ subs: [String: [String]], _ tables: DerivationTables) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (head, members) in subs {
            guard let blocked = tables.elementBlock[head], let headType = tables.elementTypeNames[head] else {
                result[head] = members
                continue
            }
            result[head] = members.filter { member in
                // `block="substitution"` forbids substitution-group substitution
                // outright: no member may stand in for the head, whatever its type.
                guard !blocked.contains(.substitution) else { return false }
                guard let memberType = tables.elementTypeNames[member],
                      let methods = derivationMethods(from: memberType, to: headType, tables.typeDerivation)
                else {
                    return true
                }
                return methods.isDisjoint(with: blocked)
            }
        }
        return result
    }

    private static func methodName(_ method: PureXML.Schema.DerivationMethod) -> String {
        switch method {
        case .extension: "extension"
        case .restriction: "restriction"
        case .substitution: "substitution"
        }
    }

    /// Throws when any `xs:all` group violates its XSD 1.0 constraints: its members
    /// must all be elements, each occurring at most once, and the group itself may
    /// occur at most once. Nested model groups inside an `all` are not allowed.
    static func checkAllGroups(_ containers: [XSDTree]) throws {
        for container in containers {
            for all in descendants(container, named: "all") {
                try checkAllGroup(all)
            }
        }
    }

    private static func checkAllGroup(_ all: XSDTree) throws {
        if !atMostOnce(XSDDerivNode.attribute(all, "maxOccurs")) {
            throw SchemaFault.invalidAllGroup(reason: "the group's maxOccurs must be 0 or 1")
        }
        for member in XSDDerivNode.elementChildren(all) {
            let kind = XSDDerivNode.localName(member) ?? ""
            if kind == "annotation" { continue }
            guard kind == "element" else {
                throw SchemaFault.invalidAllGroup(reason: "a member may only be an element, not '\(kind)'")
            }
            if !atMostOnce(XSDDerivNode.attribute(member, "maxOccurs")) {
                let label = XSDDerivNode.attribute(member, "name") ?? XSDDerivNode.attribute(member, "ref") ?? ""
                throw SchemaFault.invalidAllGroup(reason: "element '\(label)' must have maxOccurs 0 or 1")
            }
        }
    }

    private static func atMostOnce(_ maxOccurs: String?) -> Bool {
        guard let maxOccurs else { return true }
        return maxOccurs == "0" || maxOccurs == "1"
    }
}
