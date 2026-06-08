/// Located, recovering RELAX NG diagnostics: one error per problem, the way an
/// editor surfaces every issue in a faulty document at once rather than stopping
/// at the first. Validity is decided by ``RelaxNGEngine/matches(start:root:)``;
/// this walk only places and explains the failures and recovers past each so the
/// rest still surface, so a valid document yields none.
extension PureXML.Schema.RelaxNGEngine {
    typealias Pattern = PureXML.Schema.Pattern
    typealias Failure = PureXML.Validation.ValidationError
    typealias PathKey = PureXML.Validation.PathKey

    func locatedErrors(start: Pattern, root: PureXML.Model.Element) -> [Failure] {
        guard !matches(start: start, root: .element(root)) else { return [] }
        var errors: [Failure] = []
        let path: [PathKey] = [.element(root.name.description)]
        let opened = startTagOpenDeriv(start, root.name)
        if isNotAllowed(opened) {
            errors.append(.init(reason: "element <\(root.name.description)> is not a valid document root\(expected(start))", at: path))
        } else {
            validateElement(opened, root, path, &errors)
        }
        if errors.isEmpty { errors.append(.init(reason: "does not satisfy the RELAX NG schema", at: path)) }
        return errors
    }

    private func isNotAllowed(_ pattern: Pattern) -> Bool {
        if case .notAllowed = pattern { return true }
        return false
    }

    /// Validates one element already matched at its start tag (`opened` is its
    /// `after(content, …)` form): its attributes, then its children against the
    /// content peeled from `opened`.
    private func validateElement(_ opened: Pattern, _ element: PureXML.Model.Element, _ path: [PathKey], _ errors: inout [Failure]) {
        let name = element.name.description
        let before = errors.count
        var residual = opened
        for attribute in element.attributes where !Self.isNamespaceDeclaration(attribute) {
            let next = attributeDeriv(residual, attribute)
            if isNotAllowed(next) {
                errors.append(.init(
                    reason: "attribute @\(attribute.name.description) is not allowed on <\(name)> or has an invalid value",
                    at: path + [.attribute(attribute.name.description)],
                ))
            } else {
                residual = next
            }
        }
        let closed = startTagCloseDeriv(residual)
        if isNotAllowed(closed) {
            // A genuine missing/extra attribute, unless an attribute error above
            // already explains why the requirement is unsatisfied (no cascade).
            if errors.count == before { errors.append(.init(reason: "element <\(name)> is missing a required attribute", at: path)) }
            return
        }
        // An attribute problem leaves the content model unreliable; stop here so a
        // value error does not also surface as bogus content errors.
        guard errors.count == before else { return }
        validateChildren(contentOf(closed), element, path, &errors)
    }

    /// Threads the children through `content`, recording each that does not fit,
    /// recovering so later children are still checked, and recursing into every
    /// well-placed child element. A sequencing failure at this level suppresses a
    /// redundant "missing content"; a deep subtree error does not.
    private func validateChildren(_ content: Pattern, _ element: PureXML.Model.Element, _ path: [PathKey], _ errors: inout [Failure]) {
        let name = element.name.description
        let totals = Self.elementNameCounts(element.children)
        var seen: [String: Int] = [:]
        var residual = content
        var sequenceBroken = false
        for node in Self.coalesceText(element.children) where !Self.isWhitespaceText(node) {
            switch node {
            case let .text(value), let .cdata(value):
                let next = textDeriv(residual, value)
                if isNotAllowed(next) {
                    errors.append(.init(reason: "text content is not valid in <\(name)>", at: path))
                    sequenceBroken = true
                } else {
                    residual = next
                }
            case let .element(child):
                let childName = child.name.description
                seen[childName, default: 0] += 1
                let index = (totals[childName] ?? 0) > 1 ? seen[childName] : nil
                let childPath = path + [.element(childName, index: index)]
                let unexpected: Bool
                (residual, unexpected) = consumeChild(residual, child, parent: name, path: childPath, errors: &errors)
                sequenceBroken = sequenceBroken || unexpected
            default:
                break
            }
        }
        if !sequenceBroken, !nullable(residual) {
            errors.append(.init(reason: "element <\(name)> is missing required content\(expected(residual))", at: path))
        }
    }

    /// Consumes one child element, recursing into it. Returns the residual for the
    /// next sibling and whether the child was unexpected here (a sequencing break,
    /// as opposed to a child that fit but whose own content was invalid).
    private func consumeChild(
        _ residual: Pattern,
        _ child: PureXML.Model.Element,
        parent: String,
        path: [PathKey],
        errors: inout [Failure],
    ) -> (Pattern, Bool) {
        let name = child.name.description
        let opened = startTagOpenDeriv(residual, child.name)
        if isNotAllowed(opened) {
            errors.append(.init(reason: "element <\(name)> is not expected in <\(parent)>\(expected(residual))", at: path))
            return (residual, true)
        }
        validateElement(opened, child, path, &errors)
        return (forceClose(opened), false)
    }

    /// The content (the `after` left side) an opened element's children must match.
    private func contentOf(_ pattern: Pattern) -> Pattern {
        switch pattern {
        case let .choice(lhs, rhs): choice(contentOf(lhs), contentOf(rhs))
        case let .after(lhs, _): lhs
        default: .notAllowed
        }
    }

    /// The residual after accepting an element regardless of its content validity,
    /// so sibling checking continues (the recovery step).
    private func forceClose(_ pattern: Pattern) -> Pattern {
        switch pattern {
        case let .choice(lhs, rhs): choice(forceClose(lhs), forceClose(rhs))
        case let .after(_, rhs): rhs
        default: .notAllowed
        }
    }

    /// A "; expected a, b" hint naming the element types the pattern accepts next,
    /// for recovery guidance. Empty when only wildcards or text are expected.
    private func expected(_ pattern: Pattern) -> String {
        let names = Set(expectedNames(pattern, visiting: [])).sorted()
        return names.isEmpty ? "" : "; expected \(names.joined(separator: ", "))"
    }

    private func expectedNames(_ pattern: Pattern, visiting: Set<String>) -> [String] {
        switch pattern {
        case let .element(nameClass, _): literalNames(nameClass)
        case let .choice(lhs, rhs), let .interleave(lhs, rhs): expectedNames(lhs, visiting: visiting) + expectedNames(rhs, visiting: visiting)
        case let .group(lhs, rhs): expectedNames(lhs, visiting: visiting) + (nullable(lhs) ? expectedNames(rhs, visiting: visiting) : [])
        case let .oneOrMore(inner), let .list(inner): expectedNames(inner, visiting: visiting)
        case let .after(lhs, _): expectedNames(lhs, visiting: visiting)
        case let .ref(name): visiting.contains(name) ? [] : expectedNames(resolve(name), visiting: visiting.union([name]))
        default: []
        }
    }

    private func literalNames(_ nameClass: PureXML.Schema.NameClass) -> [String] {
        switch nameClass {
        case let .name(_, local): ["<\(local)>"]
        case let .choice(lhs, rhs): literalNames(lhs) + literalNames(rhs)
        default: []
        }
    }
}
