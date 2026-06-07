public extension PureXML.Parsing {
    /// A position in the source text, used for parser diagnostics.
    struct Mark: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// One-based line number.
        public var line: Int
        /// One-based column number.
        public var column: Int
        /// Zero-based scalar offset from the start of the input.
        public var offset: Int

        public init(line: Int, column: Int, offset: Int) {
            self.line = line
            self.column = column
            self.offset = offset
        }

        /// The start of any input.
        public static let start = Mark(line: 1, column: 1, offset: 0)

        public var description: String {
            "line \(line), column \(column)"
        }
    }
}
