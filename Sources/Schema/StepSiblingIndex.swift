/// Caches, per parent element and child local name, the one-based position of
/// each same-name element child among its like-named siblings, used to locate an
/// identity-constraint error precisely (`item[3]` rather than `item`).
///
/// Without it, ``IdentityValidator/steps(from:to:)`` rescans a parent's whole
/// child list for every target it locates, so validating a wide list of like-
/// named elements is O(n) per target and quadratic overall. The first lookup
/// under a given parent and name builds the position table once; later lookups
/// are dictionary reads. A position is recorded only when more than one element
/// shares the name, matching the path grammar, which omits the predicate for a
/// unique child.
final class StepSiblingIndex {
    typealias Tree = PureXML.Model.TreeNode

    /// parent identity -> child local name -> child identity -> one-based
    /// position among same-name element siblings (present only when several
    /// siblings share the name).
    private var positions: [ObjectIdentifier: [String: [ObjectIdentifier: Int]]] = [:]

    /// The one-based position of `node` among `parent`'s element children named
    /// `name`, or nil when it is the only such child (no predicate needed).
    func position(of node: Tree, under parent: Tree, name: String) -> Int? {
        let parentIdentity = ObjectIdentifier(parent)
        if let table = positions[parentIdentity]?[name] {
            return table[ObjectIdentifier(node)]
        }
        var table: [ObjectIdentifier: Int] = [:]
        var ordinal = 0
        for child in parent.children where child.kind == .element && (child.name?.description ?? "") == name {
            ordinal += 1
            table[ObjectIdentifier(child)] = ordinal
        }
        // The grammar predicates a step only when the name is ambiguous; a single
        // same-name child keeps the bare `name`, so drop a lone entry.
        if ordinal < 2 { table = [:] }
        positions[parentIdentity, default: [:]][name] = table
        return table[ObjectIdentifier(node)]
    }
}
