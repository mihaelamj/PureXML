/// One distinct particle occurrence in a content model: its source-node identity
/// and label. A particle never conflicts with a repetition of itself, so identity,
/// not label alone, decides conflict (per the UPA semantics). File-private.
private struct CompItem: Hashable {
    let particle: ObjectIdentifier
    let label: PureXML.Schema.TermLabel

    static func == (lhs: CompItem, rhs: CompItem) -> Bool {
        lhs.particle == rhs.particle
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(particle)
    }
}

/// The context-independent summary of a sub-model: nullability, the items that can
/// start it (`first`), and, for each item that can END it, the items that follow
/// that end-item INTERNALLY (`followlast`, e.g. the loop-back of a repetition or
/// the cross-edges of an `all`). The parent forms a gap's decision set by combining
/// a child's `followlast` with the first of what comes next.
private struct CompSummary {
    var nullable: Bool
    var first: [CompItem]
    /// Each end-item paired with its internal follow set.
    var lastFollow: [(item: CompItem, follow: [CompItem])]
}

extension PureXML.Schema {
    /// A compositional Unique Particle Attribution (1-unambiguity) check that does
    /// NOT inline `<xs:group ref>`: each group is summarized once, so a
    /// multiply-referenced nested group cannot blow up to `2^K` positions (which is
    /// why the former inlining Glushkov automaton needed a `positionCap` skip).
    /// Cross-boundary decision sets are formed at each reference site, so two
    /// reference contexts never merge (that merge would be a false positive).
    ///
    /// This is the authoritative determinism check (`ContentModelDeterminism`
    /// delegates to it). It was proven verdict-equivalent to the prior inlining
    /// automaton by a differential over the whole XSTS corpus (zero divergences)
    /// before replacing it. See docs/design/counted-content-automaton.md.
    enum CompositionalDeterminism {
        /// A UPA-violation message for the content model formed by `models` in
        /// sequence (a complexContent extension's effective content), or nil.
        static func violation(_ models: [XSDTree], _ bindings: [String: String], _ context: XSDContext) -> String? {
            var walk = CompWalk(bindings: bindings, context: context)
            let summary = walk.sequence(models.map { walk.summarize($0, visiting: []) })
            // The root's entry decision set, plus the followpos of each item that can
            // end the whole model (nothing follows the root, so its followpos is just
            // its internal follow).
            walk.emit(summary.first)
            for entry in summary.lastFollow {
                walk.emit(entry.follow)
            }
            for set in walk.decisionSets {
                if let conflict = CompWalk.overlap(set) {
                    return "ambiguous content model: '\(conflict)' can be matched by more than one particle"
                }
            }
            return nil
        }
    }
}

/// The mutable walk state, so the recursive helpers take few parameters and the
/// group cache / decision-set accumulator are threaded without inout chains.
private struct CompWalk {
    let bindings: [String: String]
    let context: PureXML.Schema.XSDContext
    var decisionSets: [[CompItem]] = []
    var groupCache: [String: CompSummary] = [:]

    mutating func emit(_ set: [CompItem]) {
        if set.count > 1 { decisionSets.append(set) }
    }

    mutating func summarize(_ node: PureXML.Model.TreeNode, visiting: Set<String>) -> CompSummary {
        let (minimum, maximum) = PureXML.Schema.XSDNode.occurrence(node)
        if let maximum, maximum <= 0 { return CompSummary(nullable: true, first: [], lastFollow: []) }
        var body = bodySummary(node, visiting: visiting)
        // A repeat edge (last -> first) is added for a true repetition (max unbounded or >= 2) with min < max. A
        // fixed `{n,n}` clamps to copies sharing the body's particle identities (no new
        // conflict); a `{0,1}` is optional, not a repetition. The loop folds the body's
        // first into every end-item's follow, so a later gap (or the root) checks the
        // combined loop+continuation decision set.
        if minimum != maximum, maximum == nil || (maximum ?? 0) > 1 {
            body.lastFollow = body.lastFollow.map { (item: $0.item, follow: $0.follow + body.first) }
        }
        return CompSummary(nullable: minimum == 0 || body.nullable, first: body.first, lastFollow: body.lastFollow)
    }

    private mutating func bodySummary(_ node: PureXML.Model.TreeNode, visiting: Set<String>) -> CompSummary {
        switch PureXML.Schema.XSDNode.localName(node) {
        case "element":
            let item = CompItem(particle: ObjectIdentifier(node), label: .name(elementQName(node)))
            return CompSummary(nullable: false, first: [item], lastFollow: [(item, [])])
        case "any":
            let item = CompItem(particle: ObjectIdentifier(node), label: .wildcard(PureXML.Schema.XSDParser.wildcard(node, context)))
            return CompSummary(nullable: false, first: [item], lastFollow: [(item, [])])
        case "sequence":
            return sequence(children(node, visiting: visiting))
        case "choice":
            return choice(children(node, visiting: visiting))
        case "all":
            return all(children(node, visiting: visiting))
        case "group":
            return group(node, visiting: visiting)
        default:
            return CompSummary(nullable: true, first: [], lastFollow: [])
        }
    }

    private mutating func children(_ node: PureXML.Model.TreeNode, visiting: Set<String>) -> [CompSummary] {
        PureXML.Schema.XSDNode.elementChildren(node)
            .filter { ["element", "sequence", "choice", "all", "group", "any"].contains(PureXML.Schema.XSDNode.localName($0) ?? "") }
            .map { summarize($0, visiting: visiting) }
    }

    /// A `sequence`: at each gap, every item that can end the preceding nullable run
    /// has its internal follow combined with the first of the following nullable run
    /// into one decision set (the real `followpos` of that end-item inside the
    /// sequence). The sequence's own `lastFollow` is its trailing nullable suffix's
    /// end-items, carried up for the parent to combine with whatever follows.
    mutating func sequence(_ parts: [CompSummary]) -> CompSummary {
        for index in parts.indices {
            var suffixFirst: [CompItem] = []
            for next in parts[(index + 1)...] {
                suffixFirst.append(contentsOf: next.first)
                if !next.nullable { break }
            }
            guard !suffixFirst.isEmpty else { continue }
            for entry in parts[index].lastFollow {
                emit(entry.follow + suffixFirst)
            }
        }
        var first: [CompItem] = []
        for part in parts {
            first.append(contentsOf: part.first)
            if !part.nullable { break }
        }
        var lastFollow: [(item: CompItem, follow: [CompItem])] = []
        for part in parts.reversed() {
            lastFollow.append(contentsOf: part.lastFollow)
            if !part.nullable { break }
        }
        return CompSummary(nullable: parts.allSatisfy(\.nullable), first: first, lastFollow: lastFollow)
    }

    private mutating func choice(_ parts: [CompSummary]) -> CompSummary {
        let first = parts.flatMap(\.first)
        emit(first)
        return CompSummary(
            nullable: parts.isEmpty || parts.contains(where: \.nullable),
            first: first,
            lastFollow: parts.flatMap(\.lastFollow),
        )
    }

    /// `all`: members are order-independent, so each may follow every other. Each
    /// member's end-items therefore follow (internally) every OTHER member's first,
    /// and the union of member firsts is one decision set (the entry). The cross
    /// follow is recorded in `followlast` so a parent gap combines it with the suffix
    /// (mirrors `ContentModelDeterminism.all`).
    private mutating func all(_ parts: [CompSummary]) -> CompSummary {
        let first = parts.flatMap(\.first)
        emit(first)
        var lastFollow: [(item: CompItem, follow: [CompItem])] = []
        for (index, part) in parts.enumerated() {
            let others = parts.enumerated().filter { $0.offset != index }.flatMap(\.element.first)
            for entry in part.lastFollow {
                lastFollow.append((entry.item, entry.follow + others))
            }
        }
        return CompSummary(
            nullable: parts.isEmpty || parts.allSatisfy(\.nullable),
            first: first,
            lastFollow: lastFollow,
        )
    }

    private mutating func group(_ node: PureXML.Model.TreeNode, visiting: Set<String>) -> CompSummary {
        guard let ref = PureXML.Schema.XSDNode.attribute(node, "ref") else { return CompSummary(nullable: true, first: [], lastFollow: []) }
        let name = PureXML.Schema.XSDNode.stripPrefix(ref)
        if let cached = groupCache[name] { return cached }
        guard !visiting.contains(name), let definition = context.groups[name],
              let model = PureXML.Schema.XSDNode.elementChildren(definition).first(where: { ["sequence", "choice", "all"].contains(PureXML.Schema.XSDNode.localName($0) ?? "") })
        else { return CompSummary(nullable: true, first: [], lastFollow: []) }
        // Summarize the group once: its internal decision sets are context-independent
        // and emitted here; its cross-boundary follow is formed by each reference site.
        let summary = summarize(model, visiting: visiting.union([name]))
        groupCache[name] = summary
        return summary
    }

    // MARK: Conflict

    static func overlap(_ set: [CompItem]) -> String? {
        var nameOwner: [PureXML.Model.QualifiedName: ObjectIdentifier] = [:]
        var wildcards: [(card: PureXML.Schema.Wildcard, particle: ObjectIdentifier)] = []
        for item in set {
            switch item.label {
            case let .name(qname):
                if let owner = nameOwner[qname], owner != item.particle { return qname.localName }
                if nameOwner[qname] == nil { nameOwner[qname] = item.particle }
            case let .wildcard(card):
                wildcards.append((card, item.particle))
            }
        }
        for (index, wildcard) in wildcards.enumerated() {
            // A wildcard conflicts with any name it admits, from a distinct particle,
            // and with any other wildcard it intersects, from a distinct particle.
            if nameOwner.contains(where: { wildcard.card.admits($0.key) && $0.value != wildcard.particle }) { return "any" }
            for other in wildcards[(index + 1)...] where other.particle != wildcard.particle && wildcardsOverlap(wildcard.card, other.card) {
                return "any"
            }
        }
        return nil
    }

    // MARK: Helpers (mirror ContentModelDeterminism)

    private func elementQName(_ node: PureXML.Model.TreeNode) -> PureXML.Model.QualifiedName {
        if let ref = PureXML.Schema.XSDNode.attribute(node, "ref") {
            return resolveQName(ref)
        }
        let name = PureXML.Schema.XSDNode.attribute(node, "name") ?? ""
        let form = PureXML.Schema.XSDNode.attribute(node, "form")
        let qualified = form == "qualified" || (form == nil && context.elementFormQualified)
        return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
    }

    private func resolveQName(_ qname: String) -> PureXML.Model.QualifiedName {
        let parts = qname.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return PureXML.Model.QualifiedName(localName: parts[1], namespaceURI: bindings[parts[0]] ?? parts[0])
        }
        return PureXML.Model.QualifiedName(localName: qname, namespaceURI: bindings[""])
    }

    static func wildcardsOverlap(_ lhs: PureXML.Schema.Wildcard, _ rhs: PureXML.Schema.Wildcard) -> Bool {
        // Two wildcards overlap when some namespace name is admitted by both. Any
        // two `not` forms always share infinitely many named namespaces; a `not`
        // form overlaps a set when the set holds a named namespace it admits.
        switch (lhs.namespace, rhs.namespace) {
        case (.any, _), (_, .any): true
        case let (.enumerated(lhsSet), .enumerated(rhsSet)): !lhsSet.isDisjoint(with: rhsSet)
        case let (.enumerated(set), .notNamespace(name)), let (.notNamespace(name), .enumerated(set)):
            set.contains { !$0.isEmpty && $0 != name }
        case let (.enumerated(set), .notAbsent), let (.notAbsent, .enumerated(set)):
            set.contains { !$0.isEmpty }
        case (.notNamespace, .notNamespace), (.notNamespace, .notAbsent),
             (.notAbsent, .notNamespace), (.notAbsent, .notAbsent):
            true
        }
    }
}
