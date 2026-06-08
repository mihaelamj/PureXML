public extension PureXML.Parsing {
    /// A half-open span of source text, from the start of a construct to just past
    /// its end. Carried on a ``PureXML/Model/TreeNode`` by the ranged reader so a
    /// located finding can be mapped back to characters in the document.
    struct SourceRange: Equatable, Sendable, CustomStringConvertible {
        /// The position of the first character of the construct.
        public var start: Mark
        /// The position just past the last character of the construct.
        public var end: Mark

        public init(start: Mark, end: Mark) {
            self.start = start
            self.end = end
        }

        public var description: String {
            "\(start.line):\(start.column)-\(end.line):\(end.column)"
        }
    }
}
