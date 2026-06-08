public extension PureXML.XPath {
    /// An error compiling or evaluating an XPath query in the supported subset.
    enum QueryError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unexpectedToken(String)
        case expectedNodeTest
        case unterminatedPredicate
        case unsupportedPredicate(String)
        /// An axis name was not one of the thirteen XPath axes.
        case unsupportedAxis(String)

        public var description: String {
            switch self {
            case .empty: "the XPath expression is empty"
            case let .unexpectedToken(token): "unexpected token '\(token)'"
            case .expectedNodeTest: "expected a node test"
            case .unterminatedPredicate: "unterminated predicate"
            case let .unsupportedPredicate(detail): "unsupported predicate: \(detail)"
            case let .unsupportedAxis(axis): "unsupported axis: \(axis)"
            }
        }
    }
}
