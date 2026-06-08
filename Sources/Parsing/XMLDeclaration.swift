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
                case "version": declaration.version = pair.value
                case "encoding": declaration.encoding = pair.value
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

        private static func standaloneFlag(_ value: String) -> Bool? {
            switch value {
            case "yes": true
            case "no": false
            default: nil
            }
        }
    }
}
