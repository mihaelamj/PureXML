/// The RELAX NG restrictions of spec sections 4.19 and 7, checked over the
/// compiled pattern algebra (refs resolved through the define table, elements
/// as context boundaries): prohibited paths (7.1), computable content types
/// (7.2), duplicate attributes (7.3), interleave constraints (7.4), the xmlns
/// name-class prohibition (4.16), and ref recursion not guarded by an element
/// (4.19).
enum RelaxNGRestrictions {
    typealias Pattern = PureXML.Schema.Pattern
    typealias NameClass = PureXML.Schema.NameClass

    static func violation(start: Pattern, defines: [String: Pattern]) -> String? {
        // Recursion detection runs on the raw patterns: it happens before the
        // notAllowed normalization (4.19 precedes 4.20).
        if let problem = RelaxNGRestrictionChecker(defines: defines).recursionProblem(start: start) {
            return problem
        }
        let checker = RelaxNGRestrictionChecker(defines: defines.mapValues(RelaxNGRestrictionChecker.normalized))
        let normalizedStart = RelaxNGRestrictionChecker.normalized(start)
        if let problem = checker.startProblem(normalizedStart) { return problem }
        return checker.elementProblems(normalizedStart)
    }
}
