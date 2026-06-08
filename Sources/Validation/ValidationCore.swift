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
    }

    /// The read-only bundle every check receives: the whole `Document` (the
    /// cross-cutting context a rule may consult), the current `Subject` value, and
    /// the coding path where it sits.
    struct ValidationContext<Subject: Validatable, Document> {
        public let document: Document
        public let subject: Subject
        public let codingPath: [PathKey]
    }

    /// A validation failure: a reason and the coding path where it occurred. The
    /// description strips a trailing period and renders the location consistently.
    struct ValidationError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        public let reason: String
        public let codingPath: [PathKey]

        public init(reason: String, at path: [PathKey]) {
            self.reason = reason
            codingPath = path
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
}

extension PureXML.Model.Node: PureXML.Validation.Validatable {}
extension PureXML.Model.Element: PureXML.Validation.Validatable {}
extension PureXML.Model.Attribute: PureXML.Validation.Validatable {}
