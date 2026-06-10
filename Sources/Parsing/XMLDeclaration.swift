public extension PureXML.Parsing {
    /// The XML declaration `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
    /// at the very start of a document: its version, the declared encoding name (if
    /// any), and the standalone document declaration (if any).
    struct XMLDeclaration: Equatable, Sendable {
        public var version: String?
        public var encoding: String?
        public var standalone: Bool?

        public init(version: String? = nil, encoding: String? = nil, standalone: Bool? = nil) {
            self.version = version
            self.encoding = encoding
            self.standalone = standalone
        }

        /// Parses the pseudo-attributes that follow `<?xml` in an XML declaration.
        /// The grammar fixes their order (`version`, then optional `encoding`, then
        /// optional `standalone`) and `standalone` must be `yes` or `no`. Returns
        /// nil when the text violates that grammar.
        static func parse(_ data: String) -> XMLDeclaration? {
            var scanner = PseudoAttributeScanner(data)
            let pairs = scanner.scan()
            guard let pairs, !pairs.isEmpty else { return nil }
            let names = pairs.map(\.name)
            guard names.first == "version", isOrdered(names) else { return nil }
            var declaration = XMLDeclaration()
            for pair in pairs {
                switch pair.name {
                case "version":
                    guard isValidVersion(pair.value) else { return nil }
                    declaration.version = pair.value
                case "encoding":
                    guard isValidEncodingName(pair.value) else { return nil }
                    declaration.encoding = pair.value
                case "standalone":
                    guard let flag = standaloneFlag(pair.value) else { return nil }
                    declaration.standalone = flag
                default: return nil
                }
            }
            return declaration
        }

        /// Whether the pseudo-attribute names appear in the grammar's fixed order
        /// with no repeats: version, then encoding, then standalone.
        private static func isOrdered(_ names: [String]) -> Bool {
            let rank = ["version": 0, "encoding": 1, "standalone": 2]
            var last = -1
            for name in names {
                guard let position = rank[name], position > last else { return false }
                last = position
            }
            return true
        }

        /// `VersionNum ::= '1.' [0-9]+`, exactly (no surrounding whitespace).
        private static func isValidVersion(_ value: String) -> Bool {
            guard value.hasPrefix("1.") else { return false }
            let digits = value.dropFirst(2)
            return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }

        /// `EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')*`.
        private static func isValidEncodingName(_ value: String) -> Bool {
            guard let first = value.first, first.isASCII, first.isLetter else { return false }
            return value.dropFirst().allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "_" || character == "-")
            }
        }

        private static func standaloneFlag(_ value: String) -> Bool? {
            switch value {
            case "yes": true
            case "no": false
            default: nil
            }
        }
    }
}
