/// Located content-model diagnostics: pinpoint which child breaks the model and
/// what was expected there, so an editor shows placed errors with recovery hints
/// rather than one opaque "content does not match" per element.
extension PureXML.Schema.ComplexValidator {
    /// Walks the children through the content automaton, flagging the first child
    /// the follow-set rejects, or the missing content when the sequence ends early.
    func sequenceStructureErrors(_ particle: PureXML.Schema.Particle, children: [PureXML.Model.Element], at path: XSDPath, into errors: inout [XSDFailure]) {
        let nfa = PureXML.Schema.ContentNFABuilder.build(particle)
        let steps = Self.childSteps(children)
        // Advance one active state-set across the children rather than re-walking
        // the prefix per child (which is quadratic over the content model, #129).
        let inputLength = children.count
        var current = nfa.startStates(inputLength: inputLength)
        for (index, child) in children.enumerated() {
            guard let next = nfa.step(current, over: child.name, inputLength: inputLength) else {
                let allowed = nfa.admissible(from: current)
                errors.append(XSDFailure(reason: "element '\(child.name.localName)' is not allowed here\(Self.expectation(allowed))", at: path + [steps[index]]))
                return
            }
            current = next
        }
        if !nfa.isComplete(current) {
            errors.append(XSDFailure(reason: "content is incomplete\(Self.expectation(nfa.admissible(from: current)))", at: path))
        }
    }

    /// Locates `all`-group violations: each child that is not an in-bounds member,
    /// recovering past it, then each required member that never appeared.
    func allStructureErrors(_ group: PureXML.Schema.Group, children: [PureXML.Model.Element], groupOptional: Bool = false, at path: XSDPath, into errors: inout [XSDFailure]) {
        var counts = [Int](repeating: 0, count: group.particles.count)
        let steps = Self.childSteps(children)
        for (index, child) in children.enumerated() {
            guard let position = group.particles.indices.first(where: { slot in
                let member = group.particles[slot]
                let room = member.maxOccurs.map { counts[slot] < $0 } ?? true
                return room && Self.memberMatches(member.term, child.name)
            }) else {
                errors.append(XSDFailure(reason: "element '\(child.name.localName)' is not allowed here", at: path + [steps[index]]))
                continue
            }
            counts[position] += 1
        }
        // An optional `all` group (`minOccurs="0"`) that contributes no children is
        // absent (zero occurrences), so its required members are not expected; but
        // once any child appears the group is present once and every member's own
        // `minOccurs` applies. A required group (`minOccurs="1"`) always enforces.
        if groupOptional, children.isEmpty { return }
        for (index, member) in group.particles.enumerated() where counts[index] < member.minOccurs {
            if case let .element(name, _, _, _, _, _) = member.term {
                errors.append(XSDFailure(reason: "element '\(name.localName)' is required but missing", at: path))
            }
        }
    }

    static func memberMatches(_ term: PureXML.Schema.Term, _ name: PureXML.Model.QualifiedName) -> Bool {
        switch term {
        case let .element(declared, _, _, _, _, _): declared.localName == name.localName && declared.namespaceURI == name.namespaceURI
        case let .wildcard(wildcard): wildcard.admits(name)
        case .group: false
        }
    }

    /// The particle each child of an `all` group matched, for per-child
    /// assessment. `all` is matched by counting, not by the automaton, so it has
    /// its own pass mirroring ``allStructureErrors``.
    func allMatchedParticles(_ group: PureXML.Schema.Group, children: [PureXML.Model.Element]) -> [PureXML.Schema.MatchedParticle?] {
        var counts = [Int](repeating: 0, count: group.particles.count)
        var result: [PureXML.Schema.MatchedParticle?] = []
        for child in children {
            guard let slot = group.particles.indices.first(where: { index in
                let member = group.particles[index]
                let room = member.maxOccurs.map { counts[index] < $0 } ?? true
                return room && Self.memberMatches(member.term, child.name)
            }) else {
                result.append(nil)
                continue
            }
            counts[slot] += 1
            result.append(Self.matchedParticle(of: group.particles[slot].term))
        }
        return result
    }

    static func matchedParticle(of term: PureXML.Schema.Term) -> PureXML.Schema.MatchedParticle? {
        switch term {
        case let .element(_, type, _, valueConstraint, _, _): .element(type: type, valueConstraint: valueConstraint)
        case let .wildcard(wildcard): .wildcard(wildcard)
        case .group: nil
        }
    }

    /// A "; expected a, b" hint naming the elements the automaton accepts next.
    static func expectation(_ labels: [PureXML.Schema.TermLabel]) -> String {
        let names = labels.compactMap { label -> String? in
            if case let .name(qualified) = label { return "<\(qualified.localName)>" }
            return nil
        }
        let unique = Set(names).sorted()
        return unique.isEmpty ? "" : "; expected \(unique.joined(separator: ", "))"
    }
}
