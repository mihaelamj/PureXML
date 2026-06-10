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

        /// Whether to process a `<!DOCTYPE>` internal subset at all. Off by default:
        /// rejecting DTDs removes the XXE and entity-expansion threat classes. When
        /// on, only internal general entities are honored; external entities are
        /// still refused, and expansion is bounded by ``maxEntityExpansion``.
        public var allowDoctype: Bool
        /// When true, the internal DTD subset is held to the letter of XML
        /// 1.0: conditional sections and parameter-entity references inside
        /// markup declarations are rejected (the spec reserves both for the
        /// external subset). Off by default; PureXML supports them as
        /// features.
        public var strictInternalSubset: Bool

        /// The maximum number of characters that internal-entity expansion may
        /// produce across the whole document. The cap (not the literal document
        /// size) is what defends against billion-laughs amplification.
        public var maxEntityExpansion: Int

        public init(
            maxDepth: Int = 256,
            maxNameLength: Int = 50000,
            maxContentLength: Int = 10_000_000,
            allowDoctype: Bool = false,
            maxEntityExpansion: Int = 1_000_000,
            strictInternalSubset: Bool = false,
        ) {
            self.maxDepth = maxDepth
            self.maxNameLength = maxNameLength
            self.maxContentLength = maxContentLength
            self.allowDoctype = allowDoctype
            self.maxEntityExpansion = maxEntityExpansion
            self.strictInternalSubset = strictInternalSubset
        }

        /// The default limits, matching libxml2's bounded-by-default posture.
        public static let `default` = Limits()
    }
}
