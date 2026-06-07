public extension PureXML.XPath {
    /// An error compiling or evaluating an XPath query in the supported subset.
    enum QueryError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unexpectedToken(String)
        case expectedNodeTest
        case unterminatedPredicate
        case unsupportedPredicate(String)
        /// An upward or sibling axis was used; only forward axes are supported.
        case unsupportedAxis(String)
        /// An attribute step appeared before the end of the path.
        case attributeStepNotLast

        public var description: String {
            switch self {
            case .empty: "the XPath expression is empty"
            case let .unexpectedToken(token): "unexpected token '\(token)'"
            case .expectedNodeTest: "expected a node test"
            case .unterminatedPredicate: "unterminated predicate"
            case let .unsupportedPredicate(detail): "unsupported predicate: \(detail)"
            case let .unsupportedAxis(axis): "unsupported axis: \(axis)"
            case .attributeStepNotLast: "an attribute step must be the last step"
            }
        }
    }
}
