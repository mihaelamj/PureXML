/// The 7.2 content classes, ordered for choice's max rule.
enum RelaxNGContentType: Comparable {
    case empty
    case complex
    case simple

    static func < (lhs: Self, rhs: Self) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ type: Self) -> Int {
        switch type {
        case .empty: 0
        case .complex: 1
        case .simple: 2
        }
    }
}
