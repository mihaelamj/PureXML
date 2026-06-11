public extension PureXML.XPath {
    /// A protective evaluation budget: the maximum node-set length a query
    /// may build. libxml2 enforces a fixed 10M-node cap and refuses larger
    /// evaluations outright; PureXML evaluates unbounded by default and
    /// lets the caller opt into a budget for untrusted input, failing with
    /// a thrown ``QueryError/budgetExceeded(_:)`` instead of a silent
    /// refusal. The counter is shared across one evaluation, including
    /// nested predicate evaluations.
    struct Budget: Sendable {
        /// The largest node-set any step or union may produce.
        public var maxNodeSetLength: Int

        public init(maxNodeSetLength: Int) {
            self.maxNodeSetLength = maxNodeSetLength
        }

        /// The libxml2-compatible cap.
        public static let libxml2Compatible = Budget(maxNodeSetLength: 10_000_000)
    }
}
