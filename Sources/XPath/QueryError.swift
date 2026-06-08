public extension PureXML.XPath {
    /// An error compiling or evaluating an XPath query.
    enum QueryError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unexpectedToken(String)
        case expectedNodeTest
        case unterminatedPredicate
        case unsupportedPredicate(String)
        /// An axis name was not one of the thirteen XPath axes.
        case unsupportedAxis(String)
        /// A function was called that is not in the library.
        case unknownFunction(String)
        /// A `$name` reference had no binding in the evaluation context.
        case undefinedVariable(String)
        /// A function received the wrong number or type of arguments.
        case invalidArguments(String)

        public var description: String {
            switch self {
            case .empty: "the XPath expression is empty"
            case let .unexpectedToken(token): "unexpected token '\(token)'"
            case .expectedNodeTest: "expected a node test"
            case .unterminatedPredicate: "unterminated predicate"
            case let .unsupportedPredicate(detail): "unsupported predicate: \(detail)"
            case let .unsupportedAxis(axis): "unsupported axis: \(axis)"
            case let .unknownFunction(name): "unknown function '\(name)()'"
            case let .undefinedVariable(name): "variable '$\(name)' is not bound"
            case let .invalidArguments(detail): "invalid arguments: \(detail)"
            }
        }
    }
}
