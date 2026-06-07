public extension PureXML.Validation {
    /// A single validation finding with a severity and human-readable message.
    struct Issue: Equatable, Hashable, Sendable, CustomStringConvertible {
        public var severity: Severity
        public var message: String

        public init(severity: Severity, message: String) {
            self.severity = severity
            self.message = message
        }

        public var description: String {
            "\(severity.rawValue): \(message)"
        }
    }
}
