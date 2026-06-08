public extension PureXML.XPointer {
    /// An error parsing an XPointer.
    enum XPointerError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case malformed
        case unknownScheme(String)

        public var description: String {
            switch self {
            case .empty: "the XPointer is empty"
            case .malformed: "the XPointer is malformed"
            case let .unknownScheme(name): "unknown XPointer scheme '\(name)'"
            }
        }
    }
}
