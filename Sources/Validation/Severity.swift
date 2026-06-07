public extension PureXML.Validation {
    /// The severity of a validation issue.
    enum Severity: String, Equatable, Hashable, Sendable, CaseIterable {
        case warning
        case error
    }
}
