public extension PureXML {
    /// One editor-facing diagnostic: a message, a severity, and the source range
    /// to highlight (nil when the location is unknown). The unified currency of
    /// ``lint(_:validate:)``: parse problems and validation findings share it.
    struct LintDiagnostic: Equatable, Sendable, CustomStringConvertible {
        public var message: String
        public var severity: Validation.Severity
        public var range: Parsing.SourceRange?

        public init(message: String, severity: Validation.Severity, range: Parsing.SourceRange?) {
            self.message = message
            self.severity = severity
            self.range = range
        }

        public var description: String {
            guard let range else { return "\(severity.rawValue): \(message)" }
            return "\(severity.rawValue): \(message) at \(range)"
        }
    }

    /// Lints a possibly-invalid document the way an editor would: reads it once
    /// into a ranged, best-effort tree (never throwing), then merges the parse
    /// diagnostics and the validation findings into one source-ranged,
    /// severity-tagged list in document order.
    ///
    /// `validate` runs over the recovered tree, so validation works even when the
    /// document is not well-formed. Pass a schema's node-based validate (for
    /// example `schema.validate`) to layer structural validation on top of
    /// well-formedness; omit it to lint well-formedness alone.
    static func lint(
        _ xml: String,
        validate: (Model.Node) -> [Validation.ValidationError] = { _ in [] },
    ) -> [LintDiagnostic] {
        let (tree, parseDiagnostics) = readTree(xml)
        var diagnostics = parseDiagnostics.map { diagnostic in
            LintDiagnostic(
                message: diagnostic.message,
                severity: .error,
                range: diagnostic.mark.map { Parsing.SourceRange(start: $0, end: $0) },
            )
        }
        for error in validate(tree.node) {
            diagnostics.append(LintDiagnostic(
                message: error.reason,
                severity: error.severity,
                range: tree.sourceRange(at: error.codingPath),
            ))
        }
        return diagnostics.sorted { ($0.range?.start.offset ?? .max) < ($1.range?.start.offset ?? .max) }
    }
}
