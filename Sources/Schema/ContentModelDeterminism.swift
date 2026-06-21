public extension PureXML.Schema {
    /// Unique Particle Attribution (cos-nonambig, XSD 1.0 3.8.6): a content model
    /// must be deterministic, so each element in an instance is attributed to one
    /// particle without lookahead. Checked on the Glushkov position automaton: the
    /// model is ambiguous iff some decision set, the start `firstpos` or any
    /// `followpos(p)`, holds two distinct positions whose labels can match the same
    /// element. No DFA subset construction is needed.
    ///
    /// This works on a LITERAL view of the raw schema tree, distinct from the
    /// compiled (instance) content model: a `ref` is one position carrying its
    /// resolved QName (prefix bindings, not the blanket target namespace), and
    /// substitution groups are NOT expanded. The overlap test is QName-only (not
    /// substitution-group-aware), so it can only under-report substitution-group
    /// ambiguities, never over-report. Those two choices remove the false overlaps
    /// (cross-namespace refs; expanded substitution members) that a check over the
    /// compiled model produced.
    enum ContentModelDeterminism {
        private static let modelGroupNames: Set<String> = ["sequence", "choice", "all"]
        private static let particleNames: Set<String> = ["element", "sequence", "choice", "all", "group", "any"]

        /// Every UPA-violation finding across the schema's complex-type content
        /// models, deduplicated by message in first-seen order. Each finding is
        /// located on the content-model node (`sequence`/`choice`/`all`/`group`)
        /// whose particles are ambiguous; a message shared by two models locates on
        /// the first, preserving the deduplicated count.
        static func violationFindings(in schema: XSDTree, context: XSDContext) -> [PureXML.Schema.SchemaLocatedFinding] {
            let bindings = namespaceBindings(schema)
            var findings: [PureXML.Schema.SchemaLocatedFinding] = []
            var seen: Set<String> = []
            forEachComplexType(schema) { complexType in
                let models = effectiveModelNodes(complexType, bindings, context, [])
                guard !models.isEmpty, let conflict = violation(models, bindings, context) else { return }
                // The conflicting particle the author can act on is in this type's own
                // content, so locate on its own content-model node.
                let node = contentModelNode(complexType) ?? complexType
                if seen.insert(conflict).inserted {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(reason: conflict, node: node))
                }
            }
            return findings
        }

        /// The prefix-to-namespace bindings declared on the schema element (its
        /// `xmlns:prefix` attributes; the default namespace under the empty key).
        private static func namespaceBindings(_ schema: XSDTree) -> [String: String] {
            var bindings: [String: String] = [:]
            for attribute in schema.attributes {
                if attribute.name.prefix == "xmlns" {
                    bindings[attribute.name.localName] = attribute.value
                } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    bindings[""] = attribute.value
                }
            }
            return bindings
        }

        /// Visits every `complexType` element in the schema document, skipping
        /// foreign annotation content.
        private static func forEachComplexType(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }
            if local == "complexType" { visit(node) }
            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                forEachComplexType(child, visit)
            }
        }

        /// A UPA-violation message for the content model formed by `models` in
        /// sequence, or nil. The effective content of a `complexContent` extension is
        /// its base's content followed by its own, so the models are built as one
        /// sequence: a base particle that can recur or end optionally then competes
        /// with the extension's leading particles, the cross-boundary
        /// non-determinism a single-node check misses (XSTS particlesZ022). For a
        /// non-extension the list is a single node, so `sequence([x])` reproduces the
        /// prior single-model automaton exactly.
        private static func violation(_ models: [XSDTree], _ bindings: [String: String], _ context: XSDContext) -> String? {
            var automaton = PureXML.Schema.PositionAutomaton()
            let root = sequence(models.map { build($0, &automaton, bindings, context, []) }, &automaton)
            // A model that hit the position cap was only partially built; skip it
            // rather than risk a result from an incomplete automaton.
            if automaton.labels.count > positionCap { return nil }
            var decisionSets = automaton.followpos
            decisionSets.append(root.first)
            for set in decisionSets {
                if let conflict = overlap(in: set, automaton: automaton) {
                    return "ambiguous content model: '\(conflict)' can be matched by more than one particle"
                }
            }
            return nil
        }

        /// A ceiling on positions per content model. A pathological schema is bounded
        /// here and its UPA check skipped (an under-rejection, never an
        /// over-rejection). Real content models are far below this.
        private static let positionCap = 4096

        private static func build(
            _ node: XSDTree,
            _ automaton: inout PureXML.Schema.PositionAutomaton,
            _ bindings: [String: String],
            _ context: XSDContext,
            _ visiting: Set<String>,
        ) -> PureXML.Schema.Positions {
            if automaton.labels.count > positionCap { return .empty }
            let (minimum, maximum) = PureXML.Schema.XSDNode.occurrence(node)
            // A `maxOccurs="0"` particle can never occur, and a negative maxOccurs is
            // malformed (flagged by occurrence-order validation): either contributes
            // nothing here, and this guards the copy count below against a bad bound.
            if let maximum, maximum <= 0 { return .empty }
            // A fixed count {n,n} is n copies in sequence with no repetition loop, so
            // `b{2,2}, b` stays the deterministic `b, b, b`. The exact count above one
            // does not change the determinism question, so it is clamped to two.
            if let maximum, minimum == maximum {
                let copies = (0 ..< Swift.min(maximum, 2)).map { _ in buildInner(node, &automaton, bindings, context, visiting) }
                return sequence(copies, &automaton)
            }
            // Here min < max. Build one copy. A self-loop (last -> first) is added
            // only when the particle can truly repeat (max unbounded or above one);
            // unrolling a repetition into separate copies would put one element in two
            // positions of a decision set and read as ambiguity, when a repetition of
            // a deterministic body is itself deterministic. A {0,1} is merely optional,
            // not a repetition, so it gets no loop. The floor sets nullability.
            let inner = buildInner(node, &automaton, bindings, context, visiting)
            if maximum == nil || (maximum ?? 0) > 1 {
                for position in inner.last {
                    automaton.followpos[position].formUnion(inner.first)
                }
            }
            return PureXML.Schema.Positions(nullable: minimum == 0 || inner.nullable, first: inner.first, last: inner.last)
        }

        private static func buildInner(
            _ node: XSDTree,
            _ automaton: inout PureXML.Schema.PositionAutomaton,
            _ bindings: [String: String],
            _ context: XSDContext,
            _ visiting: Set<String>,
        ) -> PureXML.Schema.Positions {
            switch PureXML.Schema.XSDNode.localName(node) {
            case "element":
                let position = automaton.position(.name(elementQName(node, bindings, context)), node)
                return PureXML.Schema.Positions(nullable: false, first: [position], last: [position])
            case "any":
                let position = automaton.position(.wildcard(PureXML.Schema.XSDParser.wildcard(node, context)), node)
                return PureXML.Schema.Positions(nullable: false, first: [position], last: [position])
            case "sequence":
                return sequence(childSets(node, &automaton, bindings, context, visiting), &automaton)
            case "choice":
                return choice(childSets(node, &automaton, bindings, context, visiting))
            case "all":
                return all(childSets(node, &automaton, bindings, context, visiting), &automaton)
            case "group":
                return groupReference(node, &automaton, bindings, context, visiting)
            default:
                return .empty
            }
        }

        private static func childSets(
            _ node: XSDTree,
            _ automaton: inout PureXML.Schema.PositionAutomaton,
            _ bindings: [String: String],
            _ context: XSDContext,
            _ visiting: Set<String>,
        ) -> [PureXML.Schema.Positions] {
            PureXML.Schema.XSDNode.elementChildren(node)
                .filter { particleNames.contains(PureXML.Schema.XSDNode.localName($0) ?? "") }
                .map { build($0, &automaton, bindings, context, visiting) }
        }

        /// Inlines a `group` reference's model group (its sole `all`/`choice`/
        /// `sequence`), guarding against a cyclic reference.
        private static func groupReference(
            _ node: XSDTree,
            _ automaton: inout PureXML.Schema.PositionAutomaton,
            _ bindings: [String: String],
            _ context: XSDContext,
            _ visiting: Set<String>,
        ) -> PureXML.Schema.Positions {
            guard let ref = PureXML.Schema.XSDNode.attribute(node, "ref") else { return .empty }
            let name = PureXML.Schema.XSDNode.stripPrefix(ref)
            guard !visiting.contains(name), let definition = context.groups[name],
                  let model = PureXML.Schema.XSDNode.elementChildren(definition).first(where: { modelGroupNames.contains(PureXML.Schema.XSDNode.localName($0) ?? "") })
            else { return .empty }
            return build(model, &automaton, bindings, context, visiting.union([name]))
        }

        private static func elementQName(_ node: XSDTree, _ bindings: [String: String], _ context: XSDContext) -> PureXML.Model.QualifiedName {
            if let ref = PureXML.Schema.XSDNode.attribute(node, "ref") {
                return resolveQName(ref, bindings, context)
            }
            let name = PureXML.Schema.XSDNode.attribute(node, "name") ?? ""
            let form = PureXML.Schema.XSDNode.attribute(node, "form")
            let qualified = form == "qualified" || (form == nil && context.elementFormQualified)
            return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
        }

        /// Resolves a QName reference to (localName, namespaceURI): a prefix maps
        /// through the schema's bindings (or stands for itself if unbound, keeping
        /// distinct prefixes distinct); an unprefixed name takes the default
        /// namespace binding.
        private static func resolveQName(_ qname: String, _ bindings: [String: String], _: XSDContext) -> PureXML.Model.QualifiedName {
            let parts = qname.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return PureXML.Model.QualifiedName(localName: parts[1], namespaceURI: bindings[parts[0]] ?? parts[0])
            }
            return PureXML.Model.QualifiedName(localName: qname, namespaceURI: bindings[""])
        }

        private static func sequence(_ children: [PureXML.Schema.Positions], _ automaton: inout PureXML.Schema.PositionAutomaton) -> PureXML.Schema.Positions {
            var first: Set<Int> = []
            var prefixNullable = true
            var preceding: Set<Int> = []
            for child in children {
                if prefixNullable { first.formUnion(child.first) }
                for position in preceding {
                    automaton.followpos[position].formUnion(child.first)
                }
                preceding = child.nullable ? preceding.union(child.last) : child.last
                if !child.nullable { prefixNullable = false }
            }
            var last: Set<Int> = []
            var suffixNullable = true
            for child in children.reversed() {
                if suffixNullable { last.formUnion(child.last) }
                if !child.nullable { suffixNullable = false }
            }
            return PureXML.Schema.Positions(nullable: children.allSatisfy(\.nullable), first: first, last: last)
        }

        private static func choice(_ children: [PureXML.Schema.Positions]) -> PureXML.Schema.Positions {
            PureXML.Schema.Positions(
                nullable: children.isEmpty || children.contains(where: \.nullable),
                first: children.reduce(into: Set<Int>()) { $0.formUnion($1.first) },
                last: children.reduce(into: Set<Int>()) { $0.formUnion($1.last) },
            )
        }

        /// `all`: members are order-independent, so each may follow every other and
        /// the members form one decision set; two same-named members then overlap.
        private static func all(_ children: [PureXML.Schema.Positions], _ automaton: inout PureXML.Schema.PositionAutomaton) -> PureXML.Schema.Positions {
            for source in children {
                for target in children where target.first != source.first {
                    for position in source.last {
                        automaton.followpos[position].formUnion(target.first)
                    }
                }
            }
            return choice(children)
        }

        private static func overlap(in set: Set<Int>, automaton: PureXML.Schema.PositionAutomaton) -> String? {
            let positions = set.sorted()
            for outer in 0 ..< positions.count {
                let outerPosition = positions[outer]
                for inner in (outer + 1) ..< positions.count {
                    let innerPosition = positions[inner]
                    // Two positions conflict only if they are distinct particles whose
                    // labels can match the same element; one particle's own repetition
                    // (same source) is deterministic by construction.
                    guard automaton.particles[outerPosition] != automaton.particles[innerPosition],
                          labelsOverlap(automaton.labels[outerPosition], automaton.labels[innerPosition])
                    else { continue }
                    return describe(automaton.labels[outerPosition])
                }
            }
            return nil
        }

        private static func labelsOverlap(_ lhs: TermLabel, _ rhs: TermLabel) -> Bool {
            switch (lhs, rhs) {
            case let (.name(lhsName), .name(rhsName)):
                lhsName.localName == rhsName.localName && lhsName.namespaceURI == rhsName.namespaceURI
            case let (.name(name), .wildcard(wildcard)), let (.wildcard(wildcard), .name(name)):
                wildcard.admits(name)
            case let (.wildcard(lhsCard), .wildcard(rhsCard)):
                wildcardsOverlap(lhsCard, rhsCard)
            }
        }

        private static func wildcardsOverlap(_ lhs: Wildcard, _ rhs: Wildcard) -> Bool {
            switch (lhs.namespace, rhs.namespace) {
            case (.any, _), (_, .any):
                // `##any` admits every name, so it shares names with any other constraint.
                true
            case (.other, .other):
                // Two `##other` constraints each admit every namespace but their own
                // target (and the absent namespace); those infinite sets always
                // intersect, so they overlap (XSTS wildI* non-deterministic choices).
                true
            case let (.enumerated(lhsSet), .enumerated(rhsSet)):
                !lhsSet.isDisjoint(with: rhsSet)
            case let (.other, .enumerated(set)):
                otherOverlapsEnumerated(set, target: lhs.targetNamespace)
            case let (.enumerated(set), .other):
                otherOverlapsEnumerated(set, target: rhs.targetNamespace)
            }
        }

        /// Whether `##other` (any namespace but the target and the absent namespace)
        /// shares a name with an enumerated set: it does iff the set names some
        /// namespace that is neither absent (the empty string, `##local`) nor the
        /// target namespace `##other` excludes.
        private static func otherOverlapsEnumerated(_ set: Set<String>, target: String?) -> Bool {
            set.contains { !$0.isEmpty && $0 != (target ?? "") }
        }

        private static func describe(_ label: TermLabel) -> String {
            switch label {
            case let .name(name): name.localName
            case .wildcard: "any"
            }
        }
    }

    /// The firstpos/lastpos/nullable summary of a sub-model, used while building the
    /// position automaton.
    private struct Positions {
        let nullable: Bool
        let first: Set<Int>
        let last: Set<Int>

        static let empty = Positions(nullable: true, first: [], last: [])
    }

    /// The Glushkov position automaton under construction: one entry per position
    /// for its transition label, its `followpos` set, and the source particle it
    /// came from (Unique Particle Attribution is per particle, so a particle never
    /// conflicts with a repetition of itself).
    private struct PositionAutomaton {
        var labels: [TermLabel] = []
        var followpos: [Set<Int>] = []
        var particles: [ObjectIdentifier] = []

        mutating func position(_ label: TermLabel, _ source: XSDTree) -> Int {
            labels.append(label)
            followpos.append([])
            particles.append(ObjectIdentifier(source))
            return labels.count - 1
        }
    }
}
