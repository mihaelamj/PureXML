/// The prohibition flags one path walk carries (7.1).
struct RelaxNGPathFlags {
    var inAttribute = false
    var inOneOrMoreGroupOrInterleave = false
    var underOneOrMore = false
    var inList = false
}

/// The per-element walks: prohibited paths (7.1), with refs expanding
/// transparently and elements as the simplified grammar's ref targets.
extension RelaxNGRestrictionChecker {
    // MARK: Per-element checks (7.1-7.4, 4.16)

    /// Walks every element pattern reachable from `start`, checking its
    /// content against the path, content-type, attribute, and interleave
    /// restrictions.
    func elementProblems(_ start: Pattern) -> String? {
        var queue: [Pattern] = [start]
        var enqueuedDefines: Set<String> = []
        var seenElements = 0
        while let pattern = queue.popLast() {
            switch pattern {
            case let .element(nameClass, content):
                seenElements += 1
                if seenElements > 10000 { return nil }
                _ = nameClass
                if let problem = contentProblem(content) { return problem }
                queue.append(content)
            case let .attribute(_, content):
                queue.append(content)
            case let .choice(lhs, rhs), let .group(lhs, rhs), let .interleave(lhs, rhs):
                queue.append(lhs)
                queue.append(rhs)
            case let .oneOrMore(inner), let .list(inner), let .dataExcept(_, inner):
                queue.append(inner)
            case let .ref(name):
                if enqueuedDefines.insert(name).inserted {
                    queue.append(resolve(name))
                }
            default:
                break
            }
        }
        return nil
    }

    /// One element's content: prohibited paths under attribute, oneOrMore
    /// group/interleave, and list (7.1), a computable content type (7.2),
    /// distinct attributes (7.3), and interleave constraints (7.4).
    func contentProblem(_ content: Pattern) -> String? {
        if let problem = pathProblem(content, flags: RelaxNGPathFlags(), visiting: []) { return problem }
        if contentType(content, visiting: []) == nil {
            return "element content does not have a computable content type (7.2)"
        }
        if let problem = attributeSets(content, visiting: []).problem { return problem }
        return interleaveProblem(content, visiting: [])
    }

    func pathProblem(_ pattern: Pattern, flags: RelaxNGPathFlags, visiting: Set<String>) -> String? {
        switch pattern {
        case let .attribute(nameClass, content):
            return attributePathProblem(nameClass, content, flags: flags, visiting: visiting)
        case let .ref(name):
            guard !visiting.contains(name) else { return nil }
            return pathProblem(resolve(name), flags: flags, visiting: visiting.union([name]))
        case .text:
            return flags.inList ? "text is not allowed inside list (7.1.3)" : nil
        case .element:
            return elementPathProblem(flags)
        default:
            return compositePathProblem(pattern, flags: flags, visiting: visiting)
        }
    }

    /// The composite cases: list opens the 7.1.3 context, group and
    /// interleave under oneOrMore open the 7.1.2 context.
    private func compositePathProblem(_ pattern: Pattern, flags: RelaxNGPathFlags, visiting: Set<String>) -> String? {
        switch pattern {
        case let .list(inner):
            if flags.inList { return "list is not allowed inside list (7.1.3)" }
            var nested = flags
            nested.inList = true
            return pathProblem(inner, flags: nested, visiting: visiting)
        case let .interleave(lhs, rhs), let .group(lhs, rhs):
            if flags.inList, isInterleave(pattern) { return "interleave is not allowed inside list (7.1.3)" }
            var nested = flags
            if flags.underOneOrMore { nested.inOneOrMoreGroupOrInterleave = true }
            return pathProblem(lhs, flags: nested, visiting: visiting) ?? pathProblem(rhs, flags: nested, visiting: visiting)
        case let .choice(lhs, rhs):
            return pathProblem(lhs, flags: flags, visiting: visiting) ?? pathProblem(rhs, flags: flags, visiting: visiting)
        case let .oneOrMore(inner):
            var nested = flags
            nested.underOneOrMore = true
            return pathProblem(inner, flags: nested, visiting: visiting)
        case let .dataExcept(_, inner):
            return pathProblem(inner, flags: flags, visiting: visiting)
        default:
            return nil
        }
    }

    private func isInterleave(_ pattern: Pattern) -> Bool {
        if case .interleave = pattern { return true }
        return false
    }

    /// The attribute prohibitions of 7.1.1-7.1.3 and the infinite-name-class
    /// rule of 7.3, then the attribute's own content under the inner flag.
    private func attributePathProblem(_ nameClass: NameClass, _ content: Pattern, flags: RelaxNGPathFlags, visiting: Set<String>) -> String? {
        if flags.inAttribute { return "attribute is not allowed inside attribute (7.1.1)" }
        if flags.inOneOrMoreGroupOrInterleave {
            return "attribute is not allowed under oneOrMore with group or interleave (7.1.2)"
        }
        if flags.inList { return "attribute is not allowed inside list (7.1.3)" }
        if !flags.underOneOrMore, isInfinite(nameClass) {
            return "an attribute with an infinite name class must be inside oneOrMore (7.3)"
        }
        var inner = flags
        inner.inAttribute = true
        return pathProblem(content, flags: inner, visiting: visiting)
    }

    /// In the simplified grammar a ref stands for an element, so the
    /// prohibitions on ref under attribute and list translate to the element.
    private func elementPathProblem(_ flags: RelaxNGPathFlags) -> String? {
        if flags.inAttribute { return "element is not allowed inside attribute (7.1.1)" }
        if flags.inList { return "element is not allowed inside list (7.1.3)" }
        return nil // Otherwise a new context, walked separately.
    }

    /// Whether a name class admits infinitely many names.
    func isInfinite(_ nameClass: NameClass) -> Bool {
        switch nameClass {
        case .anyName, .anyNameExcept, .nsName, .nsNameExcept:
            true
        case let .choice(lhs, rhs):
            isInfinite(lhs) || isInfinite(rhs)
        case .name:
            false
        }
    }
}
