/// The working state of one restrictions pass. Internal to
/// ``RelaxNGRestrictions``; split across files for the length caps.
final class RelaxNGRestrictionChecker {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass

    let defines: [String: Pattern]
    private var checkedElements = 0

    init(defines: [String: Pattern]) {
        self.defines = defines
    }

    func resolve(_ name: String) -> Pattern {
        defines[name] ?? .notAllowed
    }

    /// The 4.20/4.21 normalization: notAllowed and empty operands
    /// simplify away before the restrictions are judged, so a branch the
    /// schema can never take is not checked.
    static func normalized(_ pattern: Pattern) -> Pattern {
        switch pattern {
        case let .choice(lhs, rhs):
            let left = normalized(lhs)
            let right = normalized(rhs)
            if case .notAllowed = left { return right }
            if case .notAllowed = right { return left }
            return .choice(left, right)
        case let .group(lhs, rhs):
            return combineNormalized(normalized(lhs), normalized(rhs), make: { .group($0, $1) })
        case let .interleave(lhs, rhs):
            return combineNormalized(normalized(lhs), normalized(rhs), make: { .interleave($0, $1) })
        default:
            return normalizedUnary(pattern)
        }
    }

    /// The unary cases of 4.20: a wrapper around notAllowed is notAllowed,
    /// while elements keep their (normalized) content.
    private static func normalizedUnary(_ pattern: Pattern) -> Pattern {
        switch pattern {
        case let .oneOrMore(inner):
            let normalizedInner = normalized(inner)
            if case .notAllowed = normalizedInner { return .notAllowed }
            return .oneOrMore(normalizedInner)
        case let .list(inner):
            let normalizedInner = normalized(inner)
            if case .notAllowed = normalizedInner { return .notAllowed }
            return .list(normalizedInner)
        case let .attribute(nameClass, content):
            let normalizedContent = normalized(content)
            if case .notAllowed = normalizedContent { return .notAllowed }
            return .attribute(nameClass, normalizedContent)
        case let .element(nameClass, content):
            return .element(nameClass, normalized(content))
        default:
            return pattern
        }
    }

    private static func combineNormalized(_ lhs: Pattern, _ rhs: Pattern, make: (Pattern, Pattern) -> Pattern) -> Pattern {
        if case .notAllowed = lhs { return .notAllowed }
        if case .notAllowed = rhs { return .notAllowed }
        if case .empty = lhs { return rhs }
        if case .empty = rhs { return lhs }
        return make(lhs, rhs)
    }

    // MARK: 7.1.5 start

    /// `start` admits only element, ref, choice, and notAllowed.
    func startProblem(_ pattern: Pattern, visiting: Set<String> = []) -> String? {
        switch pattern {
        case .element, .notAllowed:
            return nil
        case let .choice(lhs, rhs):
            return startProblem(lhs, visiting: visiting) ?? startProblem(rhs, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return nil }
            return startProblem(resolve(name), visiting: visiting.union([name]))
        default:
            return "start admits only element, ref, choice, and notAllowed (7.1.5)"
        }
    }

    // MARK: 4.19 recursion

    /// No define reachable from the start may reach itself through refs
    /// without an intervening element (unreachable defines are removed by
    /// the 4.19 simplification, so they are exempt).
    func recursionProblem(start: Pattern) -> String? {
        var reachable: Set<String> = []
        collectReachable(start, into: &reachable)
        for name in reachable.sorted() where reaches(resolve(name), target: name, visiting: [name]) {
            let plain = name.split(separator: "\u{1}").last.map(String.init) ?? name
            return "define '\(plain)' recurses without an intervening element (4.19)"
        }
        return nil
    }

    private func collectReachable(_ pattern: Pattern, into reachable: inout Set<String>) {
        switch pattern {
        case let .ref(name):
            guard reachable.insert(name).inserted else { return }
            collectReachable(resolve(name), into: &reachable)
        case let .choice(lhs, rhs), let .group(lhs, rhs), let .interleave(lhs, rhs):
            collectReachable(lhs, into: &reachable)
            collectReachable(rhs, into: &reachable)
        case let .oneOrMore(inner), let .list(inner), let .attribute(_, inner),
             let .element(_, inner), let .dataExcept(_, inner):
            collectReachable(inner, into: &reachable)
        default:
            break
        }
    }

    private func reaches(_ pattern: Pattern, target: String, visiting: Set<String>) -> Bool {
        switch pattern {
        case let .ref(name):
            if name == target { return true }
            guard !visiting.contains(name) else { return false }
            return reaches(resolve(name), target: target, visiting: visiting.union([name]))
        case let .choice(lhs, rhs), let .group(lhs, rhs), let .interleave(lhs, rhs):
            return reaches(lhs, target: target, visiting: visiting) || reaches(rhs, target: target, visiting: visiting)
        case let .oneOrMore(inner), let .list(inner), let .attribute(_, inner):
            return reaches(inner, target: target, visiting: visiting)
        case .element:
            return false // An element guards the recursion.
        default:
            return false
        }
    }

    // MARK: 7.2 content types

    func contentType(_ pattern: Pattern, visiting: Set<String>) -> RelaxNGContentType? {
        switch pattern {
        case .empty, .notAllowed, .attribute:
            return .empty
        case .text, .element:
            return .complex
        case .data, .value, .valueQName, .list, .dataExcept:
            return .simple
        case .choice, .group, .interleave, .oneOrMore:
            return combinedContentType(pattern, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return .complex }
            return contentType(resolve(name), visiting: visiting.union([name]))
        default:
            return .empty
        }
    }

    /// Combinator content types: choice takes the max; group, interleave, and
    /// oneOrMore additionally require groupable operands (7.2).
    private func combinedContentType(_ pattern: Pattern, visiting: Set<String>) -> RelaxNGContentType? {
        switch pattern {
        case let .choice(lhs, rhs):
            guard let left = contentType(lhs, visiting: visiting), let right = contentType(rhs, visiting: visiting) else { return nil }
            return max(left, right)
        case let .group(lhs, rhs), let .interleave(lhs, rhs):
            guard let left = contentType(lhs, visiting: visiting), let right = contentType(rhs, visiting: visiting),
                  groupable(left, right)
            else { return nil }
            return max(left, right)
        case let .oneOrMore(inner):
            guard let type = contentType(inner, visiting: visiting), groupable(type, type) else { return nil }
            return type
        default:
            return nil
        }
    }

    private func groupable(_ lhs: RelaxNGContentType, _ rhs: RelaxNGContentType) -> Bool {
        lhs == .empty || rhs == .empty || (lhs == .complex && rhs == .complex)
    }
}
