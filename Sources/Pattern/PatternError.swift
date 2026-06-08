public extension PureXML.Pattern {
    /// An error compiling a streaming pattern.
    enum PatternError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case expectedStep
        /// A construct outside the streamable subset (a predicate, an attribute
        /// step that is not last, or `.`/`..`).
        case unsupported(String)

        public var description: String {
            switch self {
            case .empty: "the pattern is empty"
            case .expectedStep: "expected a step after '/'"
            case let .unsupported(detail): "unsupported pattern construct: \(detail)"
            }
        }
    }
}
