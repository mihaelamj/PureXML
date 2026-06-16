public extension PureXML.Validation {
    /// Parse-time or advisory findings attached to a validated value, collected
    /// during traversal and returned separately from rule failures unless
    /// ``Validator/validate(_:in:strict:)`` runs with `strict: true` (the default),
    /// which promotes warnings into the thrown error collection.
    protocol HasWarnings {
        /// Advisory findings for this value at `path`. Each entry should use
        /// ``ValidationError/severity`` `.warning`.
        func validationWarnings(at path: [PathKey]) -> [ValidationError]
    }
}
