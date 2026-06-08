public extension PureXML.XInclude {
    /// An error during XInclude processing.
    enum XIncludeError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        /// An `xi:include` had no `href` and no usable fallback.
        case missingHref
        /// The resource could not be loaded and there was no `xi:fallback`.
        case unresolved(String)
        /// Includes nested past the recursion limit (a likely include loop).
        case toodeep

        public var description: String {
            switch self {
            case .missingHref: "an xi:include has no href and no fallback"
            case let .unresolved(href): "could not resolve xi:include href '\(href)' and no fallback"
            case .toodeep: "xi:include nesting is too deep (possible loop)"
            }
        }
    }
}
