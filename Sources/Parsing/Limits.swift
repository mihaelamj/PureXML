public extension PureXML.Parsing {
    /// Configurable, bounded-by-default parser limits. Exceeding any of them is a
    /// parse error rather than unbounded work, which protects against pathological
    /// input (deeply nested or oversized documents). The depth cap also keeps the
    /// recursive ``PureXML/Model/Node`` value safe to build and tear down. The
    /// defaults follow libxml2's posture.
    struct Limits: Equatable, Sendable {
        /// Maximum element nesting depth (libxml2 defaults to 256).
        public var maxDepth: Int
        /// Maximum length of a single name (element, attribute, or PI target).
        public var maxNameLength: Int
        /// Maximum length of a single text, CDATA, comment, or PI-data run.
        public var maxContentLength: Int

        public init(
            maxDepth: Int = 256,
            maxNameLength: Int = 50000,
            maxContentLength: Int = 10_000_000,
        ) {
            self.maxDepth = maxDepth
            self.maxNameLength = maxNameLength
            self.maxContentLength = maxContentLength
        }

        /// The default limits, matching libxml2's bounded-by-default posture.
        public static let `default` = Limits()
    }
}
