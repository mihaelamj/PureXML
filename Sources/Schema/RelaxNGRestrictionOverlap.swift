/// The attribute and interleave restrictions (7.3, 7.4) with the
/// representative-name overlap test for name classes.
extension RelaxNGRestrictionChecker {
    // MARK: 7.3 duplicate attributes

    func attributeSets(_ pattern: Pattern, visiting: Set<String>) -> (classes: [NameClass], problem: String?) {
        switch pattern {
        case let .attribute(nameClass, _):
            ([nameClass], nil)
        case let .choice(lhs, rhs):
            combinedAttributeSets(lhs, rhs, crossCheck: false, visiting: visiting)
        case let .group(lhs, rhs), let .interleave(lhs, rhs):
            combinedAttributeSets(lhs, rhs, crossCheck: true, visiting: visiting)
        case let .oneOrMore(inner), let .list(inner):
            attributeSets(inner, visiting: visiting)
        case let .ref(name):
            visiting.contains(name)
                ? ([], nil)
                : attributeSets(resolve(name), visiting: visiting.union([name]))
        default:
            ([], nil)
        }
    }

    /// Merges two operands' attribute classes; group and interleave require
    /// the operands' classes to be pairwise disjoint (7.3).
    private func combinedAttributeSets(_ lhs: Pattern, _ rhs: Pattern, crossCheck: Bool, visiting: Set<String>) -> (classes: [NameClass], problem: String?) {
        let left = attributeSets(lhs, visiting: visiting)
        if left.problem != nil { return left }
        let right = attributeSets(rhs, visiting: visiting)
        if right.problem != nil { return right }
        if crossCheck {
            for first in left.classes {
                for second in right.classes where nameClassesOverlap(first, second) {
                    return ([], "the same attribute may occur twice in one element (7.3)")
                }
            }
        }
        return (left.classes + right.classes, nil)
    }

    // MARK: 7.4 interleave

    func interleaveProblem(_ pattern: Pattern, visiting: Set<String>) -> String? {
        switch pattern {
        case let .interleave(lhs, rhs):
            if hasText(lhs, visiting: visiting), hasText(rhs, visiting: visiting) {
                return "text may appear in only one operand of an interleave (7.4)"
            }
            for first in elementClasses(lhs, visiting: visiting) {
                for second in elementClasses(rhs, visiting: visiting) where nameClassesOverlap(first, second) {
                    return "interleave operands share an element name (7.4)"
                }
            }
            return interleaveProblem(lhs, visiting: visiting) ?? interleaveProblem(rhs, visiting: visiting)
        case let .choice(lhs, rhs), let .group(lhs, rhs):
            return interleaveProblem(lhs, visiting: visiting) ?? interleaveProblem(rhs, visiting: visiting)
        case let .oneOrMore(inner), let .list(inner), let .attribute(_, inner), let .dataExcept(_, inner):
            return interleaveProblem(inner, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return nil }
            return interleaveProblem(resolve(name), visiting: visiting.union([name]))
        default:
            return nil
        }
    }

    private func hasText(_ pattern: Pattern, visiting: Set<String>) -> Bool {
        switch pattern {
        case .text:
            return true
        case let .choice(lhs, rhs), let .group(lhs, rhs), let .interleave(lhs, rhs):
            return hasText(lhs, visiting: visiting) || hasText(rhs, visiting: visiting)
        case let .oneOrMore(inner):
            return hasText(inner, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return false }
            return hasText(resolve(name), visiting: visiting.union([name]))
        default:
            return false
        }
    }

    private func elementClasses(_ pattern: Pattern, visiting: Set<String>) -> [NameClass] {
        switch pattern {
        case let .element(nameClass, _):
            return [nameClass]
        case let .choice(lhs, rhs), let .group(lhs, rhs), let .interleave(lhs, rhs):
            return elementClasses(lhs, visiting: visiting) + elementClasses(rhs, visiting: visiting)
        case let .oneOrMore(inner):
            return elementClasses(inner, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return [] }
            return elementClasses(resolve(name), visiting: visiting.union([name]))
        default:
            return []
        }
    }

    // MARK: Name-class overlap

    /// Overlap by representative names: every concrete name either class
    /// mentions, plus an illustrative name per nsName namespace and one in
    /// a namespace neither could mention, tested against both classes.
    private func namesClassRepresentatives(_ nameClass: NameClass, into set: inout [PureXML.Model.QualifiedName]) {
        switch nameClass {
        case let .name(namespace, localName):
            set.append(PureXML.Model.QualifiedName(prefix: nil, localName: localName, namespaceURI: namespace.isEmpty ? nil : namespace))
        case let .nsName(namespace):
            set.append(PureXML.Model.QualifiedName(prefix: nil, localName: "\u{1}illustrative", namespaceURI: namespace.isEmpty ? nil : namespace))
        case let .nsNameExcept(namespace, except):
            set.append(PureXML.Model.QualifiedName(prefix: nil, localName: "\u{1}illustrative", namespaceURI: namespace.isEmpty ? nil : namespace))
            namesClassRepresentatives(except, into: &set)
        case .anyName:
            set.append(PureXML.Model.QualifiedName(prefix: nil, localName: "\u{1}illustrative", namespaceURI: "\u{1}nowhere"))
        case let .anyNameExcept(except):
            set.append(PureXML.Model.QualifiedName(prefix: nil, localName: "\u{1}illustrative", namespaceURI: "\u{1}nowhere"))
            namesClassRepresentatives(except, into: &set)
        case let .choice(lhs, rhs):
            namesClassRepresentatives(lhs, into: &set)
            namesClassRepresentatives(rhs, into: &set)
        }
    }

    func nameClassesOverlap(_ first: NameClass, _ second: NameClass) -> Bool {
        var candidates: [PureXML.Model.QualifiedName] = []
        namesClassRepresentatives(first, into: &candidates)
        namesClassRepresentatives(second, into: &candidates)
        return candidates.contains { first.contains($0) && second.contains($0) }
    }
}
