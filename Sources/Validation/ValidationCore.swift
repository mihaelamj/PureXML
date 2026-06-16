public extension PureXML.Validation {
    /// A marker for values a ``Validation`` can specialize on. Conform the model
    /// types (and the containers traversed) so a `Validation<Subject, Document>`
    /// can fire on every `Subject` in the tree.
    protocol Validatable {}

    /// One step of a validation coding path: an element name (with an optional
    /// sibling index) or an attribute (`@name`). Conforms to the standard-library
    /// `CodingKey`, so paths render and thread without bookkeeping.
    struct PathKey: CodingKey, Equatable, Sendable {
        public var stringValue: String
        public var intValue: Int?

        public init(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        public init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }

        init(stringValue: String, intValue: Int?) {
            self.stringValue = stringValue
            self.intValue = intValue
        }

        /// An element step, optionally carrying its position among same-named
        /// siblings (rendered `name[index]`).
        static func element(_ name: String, index: Int? = nil) -> PathKey {
            PathKey(stringValue: name, intValue: index)
        }

        /// An attribute step, rendered `@name`.
        static func attribute(_ name: String) -> PathKey {
            PathKey(stringValue: "@\(name)", intValue: nil)
        }

        /// Renders a path the XML way: `root/item[2]/@id`.
        static func render(_ path: [PathKey]) -> String {
            path.map { key in
                key.intValue.map { "\(key.stringValue)[\($0)]" } ?? key.stringValue
            }.joined(separator: "/")
        }

        /// One element step per child name, carrying a one-based sibling index
        /// only when more than one child shares that name (the `xmlGetNodePath`
        /// convention). The one shared path construction behind the validator
        /// walk, the XSD content validator, and the identity validator, so
        /// located errors can never disagree on a path.
        static func steps(forChildNames names: [String]) -> [PathKey] {
            var totals: [String: Int] = [:]
            for name in names {
                totals[name, default: 0] += 1
            }
            var seen: [String: Int] = [:]
            return names.map { name in
                let index = (seen[name] ?? 0) + 1
                seen[name] = index
                return (totals[name] ?? 0) > 1 ? .element(name, index: index) : .element(name)
            }
        }
    }

    /// The read-only bundle every check receives: the whole `Document` (the
    /// cross-cutting context a rule may consult), the current `Subject` value, and
    /// the coding path where it sits.
    struct ValidationContext<Subject: Validatable, Document> {
        public let document: Document
        public let subject: Subject
        public let codingPath: [PathKey]
    }

    /// A validation finding: a reason, the coding path where it occurred, and a
    /// severity (an error by default; a warning for advisory findings such as a
    /// matched Schematron `report`). The description strips a trailing period and
    /// renders the location consistently.
    struct ValidationError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        public let reason: String
        public let codingPath: [PathKey]
        public let severity: Severity

        public init(reason: String, at path: [PathKey], severity: Severity = .error) {
            self.reason = reason
            codingPath = path
            self.severity = severity
        }

        public var description: String {
            let reasonText = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            let path = PathKey.render(codingPath)
            return path.isEmpty ? "\(reasonText) at root of document" : "\(reasonText) at path: \(path)"
        }
    }

    /// The one value thrown at the end of validation, holding every error found.
    struct ValidationErrorCollection: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        public let values: [ValidationError]

        public init(values: [ValidationError]) {
            self.values = values
        }

        public var description: String {
            values.map(\.description).joined(separator: "\n")
        }
    }

    /// Splits findings into error- and warning-severity buckets.
    static func splitFindings(_ findings: [ValidationError]) -> (errors: [ValidationError], warnings: [ValidationError]) {
        var errors: [ValidationError] = []
        var warnings: [ValidationError] = []
        for finding in findings {
            switch finding.severity {
            case .error: errors.append(finding)
            case .warning: warnings.append(finding)
            }
        }
        return (errors, warnings)
    }
}

extension PureXML.Model.Node: PureXML.Validation.Validatable {}
extension PureXML.Model.Element: PureXML.Validation.Validatable {}
extension PureXML.Model.Attribute: PureXML.Validation.Validatable {}
