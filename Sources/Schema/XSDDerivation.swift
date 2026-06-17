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
        var elementFinal: [String: Set<PureXML.Schema.DerivationMethod>] = [:]
        var elementTypeNames: [String: String] = [:]
    }

    static func derivationTables(_ containers: [XSDTree]) -> DerivationTables {
        var tables = DerivationTables()
        for container in containers {
            for type in descendants(container, named: "complexType") {
                gatherType(type, into: &tables)
            }
            for type in descendants(container, named: "simpleType") {
                gatherSimpleType(type, into: &tables)
            }
            for element in descendants(container, named: "element") {
                gatherElement(element, into: &tables)
            }
        }
        return tables
    }

    /// Records a named `simpleType`'s restriction derivation and `final` controls.
    /// A `simpleType` derives from its `restriction`'s `base`; a `list`/`union`
    /// constructs a new type (deriving from `anySimpleType`), so it is left
    /// unrecorded, which keeps two independent list/union types correctly
    /// non-derivable from one another.
    private static func gatherSimpleType(_ type: XSDTree, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        let finalSet = methodSet(XSDDerivNode.attribute(type, "final"))
        if !finalSet.isEmpty { tables.typeFinal[name] = finalSet }
        guard let restriction = XSDDerivNode.firstChild(type, named: "restriction"),
              let base = XSDDerivNode.attribute(restriction, "base") else { return }
        tables.typeDerivation[name] = PureXML.Schema.TypeDerivation(base: XSDDerivNode.stripPrefix(base), method: .restriction)
    }

    private static func gatherType(_ type: XSDTree, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        if XSDDerivNode.attribute(type, "abstract") == "true" { tables.abstractTypes.insert(name) }
        let block = methodSet(XSDDerivNode.attribute(type, "block"))
        if !block.isEmpty { tables.typeBlock[name] = block }
        let finalSet = finalMethods(of: type)
        if !finalSet.isEmpty { tables.typeFinal[name] = finalSet }
        if let derivation = derivationInfo(type) { tables.typeDerivation[name] = derivation }
    }

    private static func gatherElement(_ element: XSDTree, into tables: inout DerivationTables) {
        guard let name = XSDDerivNode.attribute(element, "name") else { return }
        if XSDDerivNode.attribute(element, "abstract") == "true" { tables.abstractElements.insert(name) }
        let block = methodSet(XSDDerivNode.attribute(element, "block"))
        if !block.isEmpty { tables.elementBlock[name] = block }

        let isGlobal = element.parent.map {
            $0.name?.namespaceURI == xsdNamespace && XSDDerivNode.localName($0) == "schema"
        } ?? false
        if isGlobal {
            let finalSet = finalMethods(of: element)
            if !finalSet.isEmpty { tables.elementFinal[name] = finalSet }
        }

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

    /// Rejects circular type derivation (XSD 1.0 `ct-props-correct.3` /
    /// `st-props-correct.2`): a complex or simple type may not derive, transitively
    /// through its `{base type definition}`, from itself. Only the base chain is
    /// followed, so a type whose *element content* recurses (an element of its own
    /// type, the normal recursive-data-structure case) is correctly permitted.
    ///
    /// A type redefined in `xs:redefine` legitimately names itself as its base (the
    /// redefinition derives from its former self), so redefined types are treated as
    /// chain ends rather than self-cycles, matching the suite's "circular ref is
    /// allowed if parent is redefine".
    static func derivationCycleErrors(_ containers: [XSDTree], _ bindings: [String: String], _ target: String?) -> [String] {
        let redefined = redefinedTypeNames(containers)
        var graph: [String: String] = [:]
        for container in containers {
            for kind in ["complexType", "simpleType"] {
                for type in descendants(container, named: kind) {
                    guard let name = XSDDerivNode.attribute(type, "name"), let base = rawBase(of: type) else { continue }
                    // Follow a base only when it resolves to this schema's own target
                    // namespace. A foreign-namespace base is resolved separately, so
                    // following it by local name would report a false self-cycle when the
                    // local names collide (a `local:X` extending an imported `other:X`).
                    guard XSDDerivNode.referenceNamespace(base, bindings) == target else { continue }
                    graph[name] = XSDDerivNode.stripPrefix(base)
                }
            }
        }
        return graph.keys.sorted().compactMap { name in
            guard !redefined.contains(name), derivesFromItself(name, graph, redefined) else { return nil }
            return "type '\(name)' must not be derived from itself"
        }
    }

    /// The raw (prefixed) base a type declares: a complex type's
    /// `complexContent`/`simpleContent` extension/restriction base, or a simple
    /// type's restriction base.
    private static func rawBase(of type: XSDTree) -> String? {
        if let derivation = XSDDerivNode.firstChild(type, named: "complexContent") ?? XSDDerivNode.firstChild(type, named: "simpleContent") {
            let node = XSDDerivNode.firstChild(derivation, named: "extension") ?? XSDDerivNode.firstChild(derivation, named: "restriction")
            return node.flatMap { XSDDerivNode.attribute($0, "base") }
        }
        return XSDDerivNode.firstChild(type, named: "restriction").flatMap { XSDDerivNode.attribute($0, "base") }
    }

    /// Whether following `start`'s base chain returns to `start`. A redefined type
    /// is a chain end (its self-naming base is the redefinition, not a cycle); a
    /// base outside the graph (a built-in, an unresolved or foreign type) ends the
    /// chain. A cycle not passing through `start` ends the walk without a match (it
    /// is reported when its own members are the start).
    private static func derivesFromItself(_ start: String, _ graph: [String: String], _ redefined: Set<String>) -> Bool {
        guard !urTypeNames.contains(start) else { return false }
        var current = start
        var seen: Set<String> = []
        while !redefined.contains(current), !urTypeNames.contains(current), let base = graph[current] {
            if base == start { return true }
            guard seen.insert(base).inserted else { return false }
            current = base
        }
        return false
    }

    /// The roots of the type hierarchy. They terminate every derivation chain, so
    /// they are never part of a cycle. The schema-for-schemas declares them in the
    /// XSD namespace with bootstrap definitions that name each other; following
    /// those would report a spurious `anySimpleType`/`string` cycle.
    private static let urTypeNames: Set<String> = ["anyType", "anySimpleType", "anyAtomicType"]

    /// The names of types redefined in an `xs:redefine`, whose `base` legitimately
    /// names themselves.
    private static func redefinedTypeNames(_ containers: [XSDTree]) -> Set<String> {
        redefinedNames(containers, "complexType").union(redefinedNames(containers, "simpleType"))
    }

    /// The names of components of `kind` redefined in an `xs:redefine`. A redefined
    /// model group or attribute group legitimately references its own former self
    /// once, so it is a chain end rather than a cycle.
    static func redefinedNames(_ containers: [XSDTree], _ kind: String) -> Set<String> {
        var names: Set<String> = []
        for container in containers where XSDDerivNode.localName(container) == "redefine" {
            for definition in XSDDerivNode.children(container, named: kind) {
                if let name = XSDDerivNode.attribute(definition, "name") { names.insert(name) }
            }
        }
        return names
    }

    /// Rejects circular references among named model groups, attribute groups, and
    /// substitution-group affiliations (XSD 1.0 `mg-props-correct.2`,
    /// `ag-props-correct.3`, `e-props-correct.6`): a group may not contain itself, an
    /// attribute group may not reference itself transitively, and a substitution
    /// chain may not loop. A reference is followed only when it resolves to this
    /// schema's own target namespace, and a redefined group/attribute group is a
    /// chain end (its single self-reference is the legal redefinition).
    static func circularReferenceErrors(_ containers: [XSDTree], _ bindings: [String: String], _ target: String?) -> [String] {
        substitutionCycleErrors(containers, bindings, target)
            + referenceCycleErrors(containers, "group", "model group", bindings, target)
            + referenceCycleErrors(containers, "attributeGroup", "attribute group", bindings, target)
    }

    private static func substitutionCycleErrors(_ containers: [XSDTree], _ bindings: [String: String], _ target: String?) -> [String] {
        var graph: [String: String] = [:]
        for container in containers {
            for element in descendants(container, named: "element") {
                guard let name = XSDDerivNode.attribute(element, "name"),
                      let head = XSDDerivNode.attribute(element, "substitutionGroup"),
                      XSDDerivNode.referenceNamespace(head, bindings) == target else { continue }
                graph[name] = XSDDerivNode.stripPrefix(head)
            }
        }
        return graph.keys.sorted().compactMap { name in
            derivesFromItself(name, graph, []) ? "element '\(name)' must not be a member of its own substitution group" : nil
        }
    }

    /// A named-definition reference cycle: a `kind` definition (`group` /
    /// `attributeGroup`) whose `kind`-references reach itself. Multi-edge, since a
    /// definition may reference several others.
    private static func referenceCycleErrors(_ containers: [XSDTree], _ kind: String, _ label: String, _ bindings: [String: String], _ target: String?) -> [String] {
        let redefined = redefinedNames(containers, kind)
        var adjacency: [String: [String]] = [:]
        for container in containers {
            for definition in descendants(container, named: kind) {
                guard let name = XSDDerivNode.attribute(definition, "name") else { continue }
                for ref in boundedReferences(definition, kind) where XSDDerivNode.referenceNamespace(ref, bindings) == target {
                    adjacency[name, default: []].append(XSDDerivNode.stripPrefix(ref))
                }
            }
        }
        return adjacency.keys.sorted().compactMap { name in
            guard !redefined.contains(name), reachesItself(name, adjacency, redefined) else { return nil }
            return "\(label) '\(name)' must not reference itself"
        }
    }

    /// The `kind`-references a definition contains *directly* in its own content,
    /// not crossing an element or type boundary. A `<group ref>` reached through an
    /// element's content model is the element's content (a recursive data
    /// structure), not the group containing itself, so the descent stops at
    /// `element`/`complexType`/`simpleType`/`attribute` scopes.
    private static func boundedReferences(_ node: XSDTree, _ kind: String) -> [String] {
        var references: [String] = []
        for child in XSDDerivNode.elementChildren(node) {
            switch XSDDerivNode.localName(child) {
            case "element", "complexType", "simpleType", "attribute":
                continue
            case kind:
                if let ref = XSDDerivNode.attribute(child, "ref") { references.append(ref) }
            default:
                references += boundedReferences(child, kind)
            }
        }
        return references
    }

    /// Whether following `start`'s references (multi-edge) returns to `start`. A
    /// sink (a redefined definition) is not expanded.
    private static func reachesItself(_ start: String, _ adjacency: [String: [String]], _ sinks: Set<String>) -> Bool {
        var visited: Set<String> = []
        var stack = adjacency[start] ?? []
        while let node = stack.popLast() {
            if node == start { return true }
            if sinks.contains(node) { continue }
            guard visited.insert(node).inserted else { continue }
            stack += adjacency[node] ?? []
        }
        return false
    }

    /// Throws when a type inside an `xs:redefine` does not derive from itself: a
    /// redefinition's `base` must name the type being redefined.
    static func checkRedefine(_ containers: [XSDTree]) throws {
        for container in containers where XSDDerivNode.localName(container) == "redefine" {
            for type in XSDDerivNode.children(container, named: "complexType") {
                guard let name = XSDDerivNode.attribute(type, "name") else { continue }
                let derivationContainer = XSDDerivNode.firstChild(type, named: "complexContent")
                    ?? XSDDerivNode.firstChild(type, named: "simpleContent")
                let rawBase = derivationContainer
                    .flatMap { XSDDerivNode.firstChild($0, named: "extension") ?? XSDDerivNode.firstChild($0, named: "restriction") }
                    .flatMap { XSDDerivNode.attribute($0, "base") }
                if derivationInfo(type)?.base != name || redefineBaseIsForeign(type, rawBase) {
                    throw SchemaFault.redefineIncompatible(type: name)
                }
            }
            for type in XSDDerivNode.children(container, named: "simpleType") {
                try checkRedefinedSimpleType(type)
            }
        }
    }

    private static func checkRedefinedSimpleType(_ type: XSDTree) throws {
        guard let name = XSDDerivNode.attribute(type, "name") else { return }
        let rawBase = XSDDerivNode.firstChild(type, named: "restriction")
            .flatMap { XSDDerivNode.attribute($0, "base") }
        if rawBase.map(XSDDerivNode.stripPrefix) != name || redefineBaseIsForeign(type, rawBase) {
            throw SchemaFault.redefineIncompatible(type: name)
        }
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
