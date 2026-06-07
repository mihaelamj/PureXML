public extension PureXML.Emitting {
    /// Explicit emitter options. The default is pretty-printed output with
    /// two-space indentation and a self-closing tag for empty elements.
    struct Options: Equatable, Hashable, Sendable {
        /// Whether to indent nested elements onto their own lines.
        public var prettyPrint: Bool
        /// The indentation unit used when ``prettyPrint`` is enabled.
        public var indent: String
        /// Whether childless elements collapse to `<name/>`.
        public var selfCloseEmptyElements: Bool

        public init(
            prettyPrint: Bool = true,
            indent: String = "  ",
            selfCloseEmptyElements: Bool = true,
        ) {
            self.prettyPrint = prettyPrint
            self.indent = indent
            self.selfCloseEmptyElements = selfCloseEmptyElements
        }

        /// Pretty-printed output with two-space indentation.
        public static let `default` = Options()

        /// Single-line output with no inserted whitespace.
        public static let compact = Options(prettyPrint: false)
    }
}
