extension PureXML.Schema.XSDNode {
    /// The transitive substitution-group membership across all definition
    /// containers: each head element maps to every element that may substitute for
    /// it, directly or through a chain of heads. Keyed by namespaced identity
    /// (`{ns}local`), so a head and a member with the same local name in different
    /// namespaces stay distinct. `namespaceMap` gives each container's resolved
    /// target namespace by index. A member whose own `block` contains
    /// `substitution` remains a member of its direct head but is not chained
    /// through to add its own members to an ancestor head.
    static func substitutionMembers(
        _ containers: [XSDTree],
        namespaceMap: [Int: String?],
        mainTargetNamespace: String?,
        chainBlockedBySubstitution: Set<String>,
    ) -> [String: [String]] {
        var direct: [String: [String]] = [:]
        for index in containers.indices {
            let container = containers[index]
            let containerNamespace = namespaceMap[index] ?? mainTargetNamespace
            for element in children(container, named: "element") {
                guard let name = attribute(element, "name"), let head = attribute(element, "substitutionGroup") else {
                    continue
                }
                let memberKey = PureXML.Schema.XSDParser.derivationKey(name, in: containerNamespace)
                let bindings = PureXML.Schema.XSDParser.namespaceBindingsInScope(of: element, defaultBindings: [:])
                let headNamespace = prefix(head) != nil ? referenceNamespace(head, bindings) : (bindings[""] ?? containerNamespace)
                let headKey = PureXML.Schema.XSDParser.derivationKey(stripPrefix(head), in: headNamespace)
                direct[headKey, default: []].append(memberKey)
            }
        }
        var closure: [String: [String]] = [:]
        for head in direct.keys {
            // Breadth-first in document order: a `popLast()` stack would reverse the
            // members, but the substitution-group expansion must stay in declaration
            // order. The order-preserving RecurseLax restriction check relies on it
            // (a base `choice(head, m1, m2)` must list `m1` before `m2` so a derived
            // `choice(m1, m2)` maps in order).
            var members: [String] = []
            var queue = direct[head] ?? []
            var seen: Set<String> = []
            var index = 0
            while index < queue.count {
                let member = queue[index]
                index += 1
                guard seen.insert(member).inserted else { continue }
                members.append(member)
                guard !chainBlockedBySubstitution.contains(member) else { continue }
                queue += direct[member] ?? []
            }
            closure[head] = members
        }
        return closure
    }
}
